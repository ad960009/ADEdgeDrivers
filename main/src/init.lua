local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local log = require "log"
local tuya_utils = require "tuya_utils" -- 🌟 여기서 한 번만 부릅니다.

-- 테이블 인덱스 에러 방지를 위해 로컬 상수로 다시 정의하거나
-- 하단 테이블에서 tuya_utils.CLUSTER_ID를 직접 사용해야 합니다.
local TUYA_CLUSTER = tuya_utils.CLUSTER_ID or 0xEF00
local TEMP_HUMID_CAP_ID = "voicewatch56866.tempAndHumidity"

local CLUSTER_TEMPERATURE = 0x0402
local CLUSTER_HUMIDITY    = 0x0405
local ATTR_MEASURED_VALUE = 0x0000

-- ====================================================================
-- 🌟 전송 래퍼 함수 (init.lua 내부에서 사용)
-- ====================================================================
local function send_tuya_command(device, dp_id, dp_type, value)
  tuya_utils.send_command(device, dp_id, dp_type, value)
  log.info(string.format("🚀 [공식 유틸 송신] DP:%d | Type:%02X | Value:%s", dp_id, dp_type, tostring(value)))
end

local function update_dashboard_text(device)
  if not device:supports_capability_by_id(TEMP_HUMID_CAP_ID) then
    return
  end

  local temp = device:get_field("last_temp") or "--"
  local humid = device:get_field("last_humid") or "--"
  local display_text = string.format("%s °C, %s %%", temp, humid)
  local custom_cap = capabilities[TEMP_HUMID_CAP_ID]
  device:emit_event(custom_cap.status({value = display_text}))
end

-- ====================================================================
-- 2. 파싱 함수 모음
-- ====================================================================
local parsers = {
  presence_complex = function(device, value)
    if value == 1 or value == 2 then
      device:emit_event(capabilities.presenceSensor.presence.present())
    else
      device:emit_event(capabilities.presenceSensor.presence.not_present())
    end
  end,
  illuminance = function(device, value, factor)
    factor = factor or 1.0
    local ill_val = value / factor
    device:emit_event(capabilities.illuminanceMeasurement.illuminance({value = ill_val}))
  end,
  temperature = function(device, value, factor)
    factor = factor or 10.0
    local temp_val = value / factor
    device:emit_event(capabilities.temperatureMeasurement.temperature({value = temp_val, unit = "C"}))
    device:set_field("last_temp", temp_val, {persist = true})
    update_dashboard_text(device)
  end,
  humidity = function(device, value, factor)
    factor = factor or 1.0
    local humid_val = value / factor
    device:emit_event(capabilities.relativeHumidityMeasurement.humidity({value = humid_val}))
    device:set_field("last_humid", humid_val, {persist = true})
    update_dashboard_text(device)
  end,
  battery_state_enum = function(device, value)
    if device:get_field("recv_battery") then
      return true
    end
    local pct = (value == 0) and 10 or (value == 1 and 50 or 100)
    device:emit_event(capabilities.battery.battery({value = pct}))
    --return true
  end,
  -- 범용 배터리
  battery = function(device, value)
    device:set_field("recv_battery", value)
    device:emit_event(capabilities.battery.battery({value = math.min(math.max(value, 0), 100)}))
  end
}

local function safe_emit_custom_event(device, cap_id, attr_id, value)
  local string_value = tostring(value)

  -- 1. 라이브러리에서 역량을 직접 가져옵니다.
  local capabilities = require "st.capabilities"
  local custom_cap = capabilities[cap_id]

  if custom_cap == nil then
    log.error(string.format("❌ 역량 로드 실패: %s", cap_id))
    return
  end

  -- 2. 역량 내부의 속성(Attribute) 객체를 가져옵니다.
  local attr = custom_cap[attr_id]

  -- 3. 표준 호출 방식 시도
  if type(attr) == "function" then
    -- 정상적인 생성자 함수인 경우
    device:emit_event(attr({ value = string_value }))
    log.info(string.format("✅ [송신:표준/F] %s -> %s", attr_id, string_value))
  else
    -- 함수가 아닌 경우(현재 상황), SDK의 가장 안전한 Fallback 메서드 사용
    -- 이 방식은 SDK 내부의 aware.lua 간섭을 최소화합니다.
    device:emit_event(custom_cap[attr_id]({ value = string_value }))
    log.info(string.format("✅ [송신:표준/A] %s -> %s", attr_id, string_value))
  end
end

-- ====================================================================
-- 3. 기기별 DP 매핑 사전
-- ====================================================================

local TEMP_HUMID_MAP = {
  [1] = { func = parsers.temperature, factor = 10.0 }, -- 온도
  [2] = { func = parsers.humidity, factor = 1.0 },     -- 습도
  [3] = { func = parsers.battery_state_enum },         -- 🌟 Z2M 기준 DP 3가 배터리 상태
  [4] = { func = parsers.battery },                    -- 배터리 잔량 (%)
  [9] = { func = function(device, val) log.info("🌡️ 단위 설정 변경됨: " .. val) end } -- 단위 설정
}

local ZTH05Z_MAP = {
  [1] = { func = parsers.temperature, factor = 10.0 }, -- 온도
  [2] = { func = parsers.humidity, factor = 1.0 },     -- 습도
  [3] = { func = parsers.battery_state_enum },         -- 배터리 상태 (Enum)
  [4] = { func = parsers.battery },                    -- 배터리 잔량 (%)
  [9] = { func = function(device, val) log.info("🌡️ 단위 설정: " .. (val == 0 and "C" or "F")) end },
  [19] = { func = function(device, val) log.info("🌡️ 온도 보고 민감도: " .. (val/10) .. "°C") end },
  [20] = { func = function(device, val) log.info("💧 습도 보고 민감도: " .. val .. "%") end },
  -- 🌟 알람 및 리포트 설정값들 (단순 로그 기록으로 WARN 제거)
  [10] = { func = function(device, val) log.info(string.format("[%s] 🔔 고온 알람 설정: %.1f°C", device.label, val/10)) end },
  [11] = { func = function(device, val) log.info(string.format("[%s] 🔔 저온 알람 설정: %.1f°C", device.label, val/10)) end },
  [12] = { func = function(device, val) log.info(string.format("[%s] 🔔 고습 알람 설정: %d%%", device.label, val)) end },
  [13] = { func = function(device, val) log.info(string.format("[%s] 🔔 저습 알람 설정: %d%%", device.label, val)) end },
  [17] = { func = function(device, val) log.info(string.format("[%s] ⏱️ 온도 보고 주기: %d분", device.label, val)) end },
  [18] = { func = function(device, val) log.info(string.format("[%s] ⏱️ 습도 보고 주기: %d분", device.label, val)) end },
  [19] = { func = function(device, val) log.info(string.format("[%s] 🎯 온도 민감도: %.1f°C", device.label, val/10)) end },
}

local DEVICE_PROFILES = {
  ["HOBEIAN"] = {
    [1] = { func = parsers.presence_complex },
    [106] = { func = parsers.illuminance, factor = 1.0 },
    [121] = { func = parsers.battery },
  },
  ["_TZE200_rhgsbacq"] = {
    [1] = { func = parsers.presence_complex },
    [106] = { func = parsers.illuminance, factor = 1.0 },
    [111] = { func = parsers.temperature, factor = 10.0 }, -- 투야 온도는 보통 10
    [101] = { func = parsers.humidity, factor = 1.0 },     -- 투야 습도는 보통 1
    [110] = { func = parsers.battery },
  },
  ["_TZE200_yjjdcqsq"] = TEMP_HUMID_MAP,
  ["_TZE204_yjjdcqsq"] = TEMP_HUMID_MAP,
  ["_TZE284_yjjdcqsq"] = TEMP_HUMID_MAP,
  ["_TZE200_upagmta9"] = TEMP_HUMID_MAP,
  ["_TZE204_upagmta9"] = TEMP_HUMID_MAP,
  ["_TZE284_upagmta9"] = TEMP_HUMID_MAP,

  ["_TZE200_vvmbj46n"] = ZTH05Z_MAP,
  ["_TZE284_vvmbj46n"] = ZTH05Z_MAP,
  ["_TZE200_w6n8jeuu"] = ZTH05Z_MAP,
  ["_TZE284_cwyqwqbf"] = ZTH05Z_MAP,
}

-- ====================================================================
-- 4. 메인 Tuya 데이터 수신기
-- ====================================================================
local function tuya_handler(driver, device, zb_rx)
  local rx_body = zb_rx.body.zcl_body.body_bytes
  if #rx_body < 6 then return end

  -- 🌟 장치 이름 가져오기 (앱에서 설정한 이름 우선, 없으면 네트워크 ID)
  local device_name = device.label or device.device_network_id or "Unknown"

  local dp_id = string.byte(rx_body, 3)
  local dp_type = string.byte(rx_body, 4)
  local data_length = (string.byte(rx_body, 5) * 256) + string.byte(rx_body, 6)

  -- 데이터 파싱 (Big-Endian)
  local data_value = 0
  if dp_type == tuya_utils.types.BOOL or dp_type == tuya_utils.types.ENUM then
    data_value = string.byte(rx_body, 7)
  elseif dp_type == tuya_utils.types.VALUE then
    -- 🌟 데이터 길이에 따른 유연한 처리 (2바이트 센서 데이터 대응)
    if data_length == 1 then
      data_value = string.byte(rx_body, 7)
    elseif data_length == 2 then
      data_value = (string.byte(rx_body, 7) * 256) + string.byte(rx_body, 8)
    elseif data_length == 4 then
      data_value = (string.byte(rx_body, 7) * 16777216) + (string.byte(rx_body, 8) * 65536) + (string.byte(rx_body, 9) * 256) + string.byte(rx_body, 10)
    end
  end

  local mfg_name = device:get_manufacturer()
  local profile = DEVICE_PROFILES[mfg_name]
  local entry = profile and profile[dp_id]

  local skip_log = false
  if entry and entry.func then
    skip_log = entry.func(device, data_value, entry.factor)
  else
    -- 🌟 로그에 장치 이름 추가
    log.warn(string.format("[%s] ⚠️ 미등록 DP: %d (Val: %d)", device_name, dp_id, data_value))
  end

  if not skip_log then
    -- 🌟 로그에 장치 이름 추가
    log.info(string.format("[%s] 📡 [수신] DP:%d | Type:%d | Value:%d", device_name, dp_id, dp_type, data_value))
  end
end

-- ====================================================================
-- 5. 앱 설정 변경 감지기 (Lifecycle)
-- ====================================================================
local function info_changed(driver, device, event, args)
  if not device.preferences then return end

  local prefs_config = {
  }

  for name, cfg in pairs(prefs_config) do
    if device.preferences[name] ~= nil and (args.old_st_store.preferences[name] ~= device.preferences[name]) then
      local val = device.preferences[name]
      local send_val

	  if cfg.type == tuya_utils.types.BOOL then
		send_val = val and 1 or 0
	  else
		send_val = math.floor((val * cfg.factor) + 0.5)
	  end

      log.info(string.format("⚙️ [송신 시도] %s -> %d", name, send_val))

      -- 🌟 수정된 유틸리티 호출
	  local dp_type = cfg.type or tuya_utils.types.VALUE
      tuya_utils.send_command(device, cfg.dp, dp_type, send_val)
    end
  end
end

-- ====================================================================
-- 🌟 기기 초기화 감지기 (Lifecycle: init)
-- ====================================================================
local function device_init(driver, device)
  log.info("==================================================")
  log.info("🟢 기기 로드 완료: " .. (device.label or device.device_network_id))
  log.info("📋 [현재 기기에 등록된 역량(Capability) 목록]")

  local has_caps = false

  -- 스마트싱스 기기 객체의 프로필 > 컴포넌트 > 역량 구조를 순회합니다.
  if device.profile and device.profile.components then
    for comp_id, component in pairs(device.profile.components) do
      for cap_id, _ in pairs(component.capabilities or {}) do
        log.info(string.format("   ✔️ [%s] %s", comp_id, cap_id))
        has_caps = true
      end
    end
  end

  if not has_caps then
    log.warn("   ⚠️ 등록된 역량이 없습니다. (프로필 매핑 오류)")
  end
  log.info("==================================================")
end

-- ====================================================================
-- 6. 드라이버 실행부
-- ====================================================================
local tuya_driver = ZigbeeDriver("ad_tuya_driver", {
  supported_capabilities = {
    capabilities.presenceSensor,
    capabilities.illuminanceMeasurement,
    capabilities.battery,
    capabilities.temperatureMeasurement,
    capabilities.relativeHumidityMeasurement,
    capabilities[TEMP_HUMID_CAP_ID],
  },
  lifecycle_handlers = {
    init = device_init, -- 🌟 기기 초기화 감지기 등록
    infoChanged = info_changed,
  },
  zigbee_handlers = {
    attr = {
      -- 표준 온도 클러스터 (0x0402)
      [CLUSTER_TEMPERATURE] = {
        [ATTR_MEASURED_VALUE] = function(driver, device, value, zb_rx)
          parsers.temperature(device, value.value, 100) -- 기존 파서 재사용
          log.info(string.format("[%s] 🌡️ 표준 온도 수신: %.2f°C", device.label, value.value / 100))
        end
      },
      -- 표준 습도 클러스터 (0x0405)
      [CLUSTER_HUMIDITY] = {
        [ATTR_MEASURED_VALUE] = function(driver, device, value, zb_rx)
          -- 습도 역시 표준은 100배 된 값으로 옵니다 (예: 5000 -> 50.0)
          parsers.humidity(device, value.value, 100) -- 기존 파서 재사용
          log.info(string.format("[%s] 💧 표준 습도 수신: %.2f%%", device.label, value.value / 100))
        end
      }
    },
    cluster = {
      -- 🌟 에러 발생 지점: TUYA_CLUSTER가 nil이면 "table index is nil" 발생
      [TUYA_CLUSTER] = {
        [0x01] = tuya_handler,
        [0x02] = tuya_handler,
        [0x24] = tuya_handler,
      }
    }
  },
})

log.info("🚀 AD Tuya 통합 드라이버 실행!")
tuya_driver:run()