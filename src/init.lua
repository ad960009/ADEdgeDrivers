local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local log = require "log"
local tuya_utils = require "tuya_utils" -- 🌟 여기서 한 번만 부릅니다.

-- 테이블 인덱스 에러 방지를 위해 로컬 상수로 다시 정의하거나
-- 하단 테이블에서 tuya_utils.CLUSTER_ID를 직접 사용해야 합니다.
local TUYA_CLUSTER = tuya_utils.CLUSTER_ID or 0xEF00

local RADAR_CAP_ID = "voicewatch56866.radarInfo"
local TEMP_HUMID_CAP_ID = "voicewatch56866.tempAndHumidity"

-- ====================================================================
-- 🌟 전송 래퍼 함수 (init.lua 내부에서 사용)
-- ====================================================================
local function send_tuya_command(device, dp_id, dp_type, value)
  tuya_utils.send_command(device, dp_id, dp_type, value)
  log.info(string.format("🚀 [공식 유틸 송신] DP:%d | Type:%02X | Value:%s", dp_id, dp_type, tostring(value)))
end

local function update_dashboard_text(device)
  if not device:supports_capability_by_id("voicewatch56866.tempAndHumidity") then
    return
  end

  local temp = device:get_field("last_temp") or "--"
  local humid = device:get_field("last_humid") or "--"
  local display_text = string.format("%s °C, %s %%", temp, humid)
  local custom_cap = capabilities["voicewatch56866.tempAndHumidity"]
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
  illuminance = function(device, value)
    device:emit_event(capabilities.illuminanceMeasurement.illuminance({value = value}))
  end,
  temperature = function(device, value)
    local temp_val = value / 10.0
    device:emit_event(capabilities.temperatureMeasurement.temperature({value = temp_val, unit = "C"}))
    device:set_field("last_temp", temp_val, {persist = true})
    update_dashboard_text(device)
  end,
  humidity = function(device, value)
    device:emit_event(capabilities.relativeHumidityMeasurement.humidity({value = value}))
    device:set_field("last_humid", value, {persist = true})
    update_dashboard_text(device)
  end,
  battery_state_enum = function(device, value)
    local pct = (value == 0) and 10 or (value == 1 and 50 or 100)
    device:emit_event(capabilities.battery.battery({value = pct}))
    return true
  end,
  -- 범용 배터리
  battery = function(device, value)
    device:emit_event(capabilities.battery.battery({value = math.min(math.max(value, 0), 100)}))
  end
}

-- 🌟 실시간 레이더 거리 처리 공통 함수 (재사용 가능)
local function handle_radar_distance(device, value)
  local last_distance = device:get_field("last_distance")

  -- 0 중복 전송 방지 최적화
  if value == 0 and last_distance == 0 then
    return true
  end

  device:set_field("last_distance", value)

  if value > 0 then
    log.info(string.format("🎯 [거리 감지] %d cm", value))
  else
    log.info("🎯 [거리 감지] 타겟 이탈 (0cm 유지 시작)")
  end

  -- 커스텀 전광판 업데이트
  if device:supports_capability_by_id("voicewatch56866.radarDistance") then
    local custom_cap = capabilities["voicewatch56866.radarDistance"]
    local display_text = ""

    if value == 0 then
      display_text = "감지 안 됨 (0 cm)"
    else
      display_text = string.format("%.2f m", value / 10.0)
    end

    device:emit_event(custom_cap.distance({value = display_text}))
  end

  return true
end

local function safe_emit_custom_event(device, cap_id, attr_id, value)
  -- 1. 기기가 해당 역량을 지원하는지 확인
  if device:supports_capability_by_id(cap_id) then
    local cap = capabilities[cap_id]

    -- 2. 역량 객체와 해당 속성 메소드가 존재하는지 검사
    if cap and type(cap[attr_id]) == "function" then
      -- 3. 존재하면 실행 (값은 {value = ...} 형태로 래핑)
      device:emit_event(cap[attr_id]({value = value}))
      log.info(string.format("✅ [이벤트 송신] %s -> %s", attr_id, tostring(value)))
    else
      -- 아직 동기화되지 않았거나 오타가 있는 경우 로그만 남기고 무시
      log.warn(string.format("⚠️ [미지원 속성] %s 역량에 '%s' 속성이 아직 없거나 동기화 전입니다.", cap_id, attr_id))
    end
  end
end

-- ====================================================================
-- 3. 기기별 DP 매핑 사전
-- ====================================================================
local DEVICE_PROFILES = {
  ["HOBEIAN"] = { [1] = parsers.presence_complex, [106] = parsers.illuminance, [121] = parsers.battery },
  ["_TZE200_rhgsbacq"] = { [1] = parsers.presence_complex, [106] = parsers.illuminance, [111] = parsers.temperature, [101] = parsers.humidity, [110] = parsers.battery },
  ["_TZE200_ya4ft0w4"] = {
    [1] = parsers.presence_complex,
    [103] = parsers.illuminance,
    [9] = handle_radar_distance,
    -- 설정 응답 로그들
    [2] = function(device, value)
      safe_emit_custom_event(device, RADAR_CAP_ID, "moveSensitivity", tostring(value))
      log.info("⚙️ [동기화] 동작 민감도: " .. value)
      return true
    end,
    [101] = function(device, value)
      local state = (value == 1 or value == true) and "켜짐 (ON)" or "꺼짐 (OFF)"
      safe_emit_custom_event(device, RADAR_CAP_ID, "distanceSwitch", state)
      log.info("⚙️ [동기화] 거리 스위치: " .. state)
      return true
    end,
    [102] = function(device, value)
      safe_emit_custom_event(device, RADAR_CAP_ID, "presenceSensitivity", tostring(value))
      log.info("⚙️ [동기화] 재실 민감도: " .. value)
      return true
    end,
    [105] = function(device, value)
      safe_emit_custom_event(device, RADAR_CAP_ID, "presenceTimeout", value .. " 초")
      log.info("⚙️ [동기화] 유지 시간: " .. value)
      return true
    end,
    [3] = function(device, value)
      local m_val = string.format("%.2f m", value / 100.0)
      safe_emit_custom_event(device, RADAR_CAP_ID, "currentMin", m_val)
      log.info("⚙️ [동기화] 최소거리: " .. m_val)
      return true
    end,
    [4] = function(device, value)
      local m_val = string.format("%.2f m", value / 100.0)
      safe_emit_custom_event(device, RADAR_CAP_ID, "currentMax", m_val)
      log.info("⚙️ [동기화] 최대거리: " .. m_val)
      return true
    end,
  },
}

-- ====================================================================
-- 4. 메인 Tuya 데이터 수신기
-- ====================================================================
local function tuya_handler(driver, device, zb_rx)
  local rx_body = zb_rx.body.zcl_body.body_bytes
  if #rx_body < 6 then return end

  local dp_id = string.byte(rx_body, 3)
  local dp_type = string.byte(rx_body, 4)
  local data_length = (string.byte(rx_body, 5) * 256) + string.byte(rx_body, 6)

  -- 데이터 파싱 (Big-Endian)
  local data_value = 0
  if dp_type == tuya_utils.types.BOOL or dp_type == tuya_utils.types.ENUM then
    data_value = string.byte(rx_body, 7)
  elseif dp_type == tuya_utils.types.VALUE and data_length == 4 then
    data_value = (string.byte(rx_body, 7) * 16777216) + (string.byte(rx_body, 8) * 65536) + (string.byte(rx_body, 9) * 256) + string.byte(rx_body, 10)
  end

  local mfg_name = device:get_manufacturer()
  local profile = DEVICE_PROFILES[mfg_name]
  local parser_func = profile and profile[dp_id]

  local skip_log = false
  if parser_func then
    skip_log = parser_func(device, data_value)
  else
    log.warn(string.format("⚠️ 미등록 DP: %d (Val: %d)", dp_id, data_value))
  end

  if not skip_log then
    log.info(string.format("📡 [수신] DP:%d | Type:%d | Value:%d", dp_id, dp_type, data_value))
  end
end

-- ====================================================================
-- 5. 앱 설정 변경 감지기 (Lifecycle)
-- ====================================================================
local function info_changed(driver, device, event, args)
  if not device.preferences then return end

  local prefs_config = {
    presenceTimeout      = { dp = 105, factor = 1 },
    presenceSensitivity  = { dp = 102, factor = 1 },
    moveSensitivity      = { dp = 2,   factor = 1 },
    detectionDistanceMin = { dp = 3,   factor = 100 },
    detectionDistanceMax = { dp = 4,   factor = 100 },
	distanceSwitch = { dp = 101, type = tuya_utils.types.BOOL, factor = 1 }
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
-- 6. 드라이버 실행부
-- ====================================================================
local tuya_driver = ZigbeeDriver("ad_tuya_driver", {
  supported_capabilities = {
    capabilities.presenceSensor,
    capabilities.illuminanceMeasurement,
    capabilities.battery,
    capabilities.temperatureMeasurement,
    capabilities.relativeHumidityMeasurement,
    capabilities.firmwareUpdate
  },
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  zigbee_handlers = {
    cluster = {
      -- 🌟 에러 발생 지점: TUYA_CLUSTER가 nil이면 "table index is nil" 발생
      [TUYA_CLUSTER] = {
        [0x01] = tuya_handler,
        [0x02] = tuya_handler,
        [0x24] = tuya_handler
      }
    }
  },
})

log.info("🚀 AD Tuya 통합 드라이버 (공식 유틸 모드) 실행!")
tuya_driver:run()