local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local log = require "log"
local tuya_utils = require "tuya_utils" -- 공식 유틸

local TUYA_CLUSTER = tuya_utils.CLUSTER_ID or 0xEF00
local CLUSTER_TEMPERATURE = 0x0402
local CLUSTER_HUMIDITY    = 0x0405
local ATTR_MEASURED_VALUE = 0x0000

local TEMP_HUMID_CAP_ID = "voicewatch56866.tempAndHumidity"
local ZG204ZK_CAP_ID = "voicewatch56866.hobeianZg204zk"

-- ====================================================================
-- 🌟 전송 래퍼 함수 (init.lua 내부에서 사용)
-- ====================================================================
local function send_tuya_command(device, dp_id, dp_type, value)
  tuya_utils.send_command(device, dp_id, dp_type, value)
  local device_name = device.label or device.device_network_id or "Unknown"
  log.info(string.format("[%s] 🚀 DP:%d | Type:%02X | Value:%s", device_name, dp_id, dp_type, tostring(value)))
end

local function update_dashboard_text(device)
  if not device:supports_capability_by_id(TEMP_HUMID_CAP_ID) then return end
  local temp = device:get_field("last_temp") or "--"
  local humid = device:get_field("last_humid") or "--"
  local display_text = string.format("%s °C, %s %%", temp, humid)
  device:emit_event(capabilities[TEMP_HUMID_CAP_ID].status({value = display_text}))
end

local capability_handlers = {
  -- HOBEIAN 레이더 센서 전용 UI 조작 핸들러
  [ZG204ZK_CAP_ID] = {
    setIndicator = function(driver, device, command)
      local send_val = (command.args.value == "on") and 1 or 0
      send_tuya_command(device, 107, tuya_utils.types.BOOL, send_val)
    end,
    setStaticDetectionDistance = function(driver, device, command)
      local send_val = math.floor((command.args.value * 100) + 0.5)
      send_tuya_command(device, 4, tuya_utils.types.VALUE, send_val)
    end,
    setStaticDetectionSensitivity = function(driver, device, command)
      send_tuya_command(device, 2, tuya_utils.types.VALUE, command.args.value)
    end,
    setMotionDetectionSensitivity = function(driver, device, command)
      send_tuya_command(device, 123, tuya_utils.types.VALUE, command.args.value)
    end,
    setFadingTime = function(driver, device, command)
      send_tuya_command(device, 102, tuya_utils.types.VALUE, command.args.value)
    end
  }
}

-- ====================================================================
-- 📡 2. 파싱 함수 및 DP 매핑 사전 (Device -> UI)
-- ====================================================================
local parsers = {
  -- 공통 파서
  presence_complex = function(device, value)
    local state = (value == 1 or value == 2 or value == true) and "present" or "not present"
    device:emit_event(capabilities.presenceSensor.presence(state))
  end,
  illuminance = function(device, value, factor)
    device:emit_event(capabilities.illuminanceMeasurement.illuminance({value = value / (factor or 1.0)}))
  end,
  temperature = function(device, value, factor)
    local temp_val = value / (factor or 10.0)
    device:emit_event(capabilities.temperatureMeasurement.temperature({value = temp_val, unit = "C"}))
    device:set_field("last_temp", temp_val, {persist = true})
    update_dashboard_text(device)
  end,
  humidity = function(device, value, factor)
    local humid_val = value / (factor or 1.0)
    device:emit_event(capabilities.relativeHumidityMeasurement.humidity({value = humid_val}))
    device:set_field("last_humid", humid_val, {persist = true})
    update_dashboard_text(device)
  end,
  battery = function(device, value)
    device:set_field("recv_battery", value)
    device:emit_event(capabilities.battery.battery({value = math.min(math.max(value, 0), 100)}))
  end,
  battery_state_enum = function(device, value)
    if device:get_field("recv_battery") then return true end
    local pct = (value == 0) and 10 or (value == 1 and 50 or 100)
    device:emit_event(capabilities.battery.battery({value = pct}))
  end,

  -- HOBEIAN 전용 커스텀 파서
  hobeian_indicator = function(device, value)
    local state = (value == 1 or value == true) and "on" or "off"
    device:emit_event(capabilities[ZG204ZK_CAP_ID].indicator(state))
  end,
  hobeian_static_dist = function(device, value)
    device:emit_event(capabilities[ZG204ZK_CAP_ID].staticDetectionDistance(value / 100.0))
  end,
  hobeian_static_sens = function(device, value)
    device:emit_event(capabilities[ZG204ZK_CAP_ID].staticDetectionSensitivity(value))
  end,
  hobeian_motion_sens = function(device, value)
    device:emit_event(capabilities[ZG204ZK_CAP_ID].motionDetectionSensitivity(value))
  end,
  hobeian_fading_time = function(device, value)
    device:emit_event(capabilities[ZG204ZK_CAP_ID].fadingTime(value))
  end
}

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

local ZG204ZK_MAP = {
  [1]   = { func = parsers.presence_complex },
  [106] = { func = parsers.illuminance, factor = 1.0 },
  [121] = { func = parsers.battery },
  [107] = { func = parsers.hobeian_indicator },
  [4]   = { func = parsers.hobeian_static_dist },
  [2]   = { func = parsers.hobeian_static_sens },
  [123] = { func = parsers.hobeian_motion_sens },
  [102] = { func = parsers.hobeian_fading_time },
}

local DEVICE_PROFILES = {
  ["HOBEIAN"] = ZG204ZK_MAP,
  ["_TZE200_rhgsbacq"] = {
    [1] = { func = parsers.presence_complex },
    [106] = { func = parsers.illuminance, factor = 1.0 },
    [111] = { func = parsers.temperature, factor = 10.0 }, -- 투야 온도는 보통 10
    [101] = { func = parsers.humidity, factor = 1.0 },     -- 투야 습도는 보통 1
    [110] = { func = parsers.battery },
    [102] = { func = parsers.hobeian_fading_time },
    [2] = { func = parsers.hobeian_static_sens},
    [108] = PARSER_UNUSED, -- indicator
    [109] = PARSER_UNUSED, -- temp unit
    [105] = PARSER_UNUSED, -- temp calibration
    [104] = PARSER_UNUSED, -- humid calibration
    [107] = PARSER_UNUSED, -- illuminance interval
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
-- 3. 메인 Tuya 데이터 수신기
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
-- 🔍 4. 상태 동기화 및 라이프사이클
-- ====================================================================
local function query_device_status(device)
  log.info("🔍 [동기화] 기기 상태 요청 (Query 0x00)")
  tuya_utils.send_query(device)
end

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

  query_device_status(device)
end

local function info_changed(driver, device, event, args)
  if not device.preferences then return end
  local prefs_config = {
-- [기존 ZG-204ZK 전용]
    prefIndicator      = { dp = 107, type = tuya_utils.types.BOOL,  factor = 1 },
    prefStaticDistance = { dp = 4,   type = tuya_utils.types.VALUE, factor = 100 },
    prefStaticSens     = { dp = 2,   type = tuya_utils.types.VALUE, factor = 1 },
    prefMotionSens     = { dp = 123, type = tuya_utils.types.VALUE, factor = 1 },
    prefFadingTime     = { dp = 102, type = tuya_utils.types.VALUE, factor = 1 },

    -- [신규 ZG-204ZV 올인원 전용] (이름 뒤에 ZV를 붙여서 충돌 방지!)
    prefIndicatorZV    = { dp = 108, type = tuya_utils.types.BOOL,  factor = 1 },
    prefMotionSensZV   = { dp = 2,   type = tuya_utils.types.VALUE, factor = 1 },
    prefFadingTimeZV   = { dp = 102, type = tuya_utils.types.VALUE, factor = 1 },
    prefIllumInterval  = { dp = 107, type = tuya_utils.types.VALUE, factor = 1 },
    prefTempCalib      = { dp = 105, type = tuya_utils.types.VALUE, factor = 10 }, -- 온도 보정은 보통 10을 곱함
    prefHumidCalib     = { dp = 104, type = tuya_utils.types.VALUE, factor = 1 }
  }

  for name, cfg in pairs(prefs_config) do
    -- 기존 설정값과 새 설정값이 다를 때만 전송 (무한 루프 방지)
    if device.preferences[name] ~= nil and (args.old_st_store.preferences[name] ~= device.preferences[name]) then
      local val = device.preferences[name]
      local send_val

      -- BOOL 타입은 1 또는 0으로, 숫자는 배율(factor) 곱해서 정수화
      if cfg.type == tuya_utils.types.BOOL then
        send_val = val and 1 or 0
      else
        send_val = math.floor((val * cfg.factor) + 0.5)
      end

      log.info(string.format("⚙️ [설정 변경 송신] %s -> %d (DP: %d)", name, send_val, cfg.dp))
      tuya_utils.send_command(device, cfg.dp, cfg.type, send_val)
    end
  end
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
    capabilities[ZG204ZK_CAP_ID],
  },

  lifecycle_handlers = {
    init = device_init, -- 🌟 기기 초기화 감지기 등록
    infoChanged = info_changed,
    added = function(driver, device)
      log.info("🎉 새 기기 추가됨: " .. (device.label or device.device_network_id))
      query_device_status(device) -- 🌟 새 기기 추가 시 상태 동기화
    end
  },

  capability_handlers = capability_handlers,

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