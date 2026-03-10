local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local log = require "log"

local TUYA_CLUSTER = 0xEF00

-- ====================================================================
-- 1. 파싱 함수 모음 (데이터를 스마트싱스 규격으로 변환)
-- ====================================================================

local parsers = {
  -- 단순 재실 (0/1 -> 존재/비어있음)
  presence_simple = function(device, value)
    if value == 1 then
      device:emit_event(capabilities.presenceSensor.presence.present())
    else
      device:emit_event(capabilities.presenceSensor.presence.not_present())
    end
  end,

  -- 복합 재실 (0:없음, 1:존재, 2:움직임 -> 모두 재실로 처리)
  presence_complex = function(device, value)
    if value == 1 or value == 2 then
      device:emit_event(capabilities.presenceSensor.presence.present())
    else
      device:emit_event(capabilities.presenceSensor.presence.not_present())
    end
  end,

  -- 조도 (값 그대로)
  illuminance = function(device, value)
    device:emit_event(capabilities.illuminanceMeasurement.illuminance({value = value}))
  end,

  -- 배터리 (0~100 보정)
  battery = function(device, value)
    local bat_val = math.min(math.max(value, 0), 100)
    device:emit_event(capabilities.battery.battery({value = bat_val}))
  end,

  -- 온도 (10으로 나누기)
  temperature = function(device, value)
    local temp_val = value / 10.0
    device:emit_event(capabilities.temperatureMeasurement.temperature({value = temp_val, unit = "C"}))
  end,

  -- 습도 (값 그대로)
  humidity = function(device, value)
    device:emit_event(capabilities.relativeHumidityMeasurement.humidity({value = value}))
  end, -- ✅ 콤마 추가됨!

  -- 배터리 상태 (0, 1, 2)
  battery_state_enum = function(device, value)
    local pct = 100
    if value == 0 then
      pct = 10  -- 배터리 없음 (Low)
    elseif value == 1 then
      pct = 50  -- 배터리 절반 (Medium)
    elseif value == 2 then
      pct = 100 -- 배터리 충분 (High)
    end

    device:emit_event(capabilities.battery.battery({value = pct}))
    log.info("🔋 앱 업데이트: 배터리 상태(" .. value .. ") -> " .. pct .. "% 로 변환")
  end,
}

-- ====================================================================
-- 2. 기기별 DP 매핑 사전
-- ====================================================================

local DEVICE_PROFILES = {
  -- 1. HOBEIAN ZG-204ZK (기존)
  ["HOBEIAN"] = {
    [1]   = parsers.presence_simple,
    [106] = parsers.illuminance,
    [121] = parsers.battery
  },

  -- 2. HOBEIAN ZG-204ZV (온습도)
  ["_TZE200_rhgsbacq"] = {
    [1]   = parsers.presence_simple,
    [106] = parsers.illuminance,
    [111] = parsers.temperature,
    [101] = parsers.humidity,
    [110] = parsers.battery
  },

  -- 3. 🆕 ZY-M100-24GV3 (복합 모션 센서)
  ["_TZE200_ya4ft0w4"] = {
    [1]   = parsers.presence_complex,
    [103] = parsers.illuminance
  }, -- ✅ 콤마 추가됨!

  -- 4. Tuya 온습도 센서 (ZTH05Z)
  ["_TZE200_vvmbj46n"] = {
    [1] = parsers.temperature,
    [2] = parsers.humidity,
    [4] = parsers.battery
  },

  -- 5. Tuya 온습도 센서 (ZTH01)
  ["_TZE204_yjjdcqsq"] = {
    [1] = parsers.temperature,
    [2] = parsers.humidity,
    [3] = parsers.battery_state_enum
  },
}

-- ====================================================================
-- 3. 메인 Tuya 데이터 수신기
-- ====================================================================

local function tuya_handler(driver, device, zb_rx)
  local rx_body = zb_rx.body.zcl_body.body_bytes
  if #rx_body < 6 then return end

  local dp_id = string.byte(rx_body, 3)
  local dp_type = string.byte(rx_body, 4)
  local data_length = (string.byte(rx_body, 5) * 256) + string.byte(rx_body, 6)

  local data_value = 0
  if dp_type == 0x01 then
    data_value = string.byte(rx_body, 7)
  elseif dp_type == 0x02 and data_length == 4 then
    data_value = (string.byte(rx_body, 7) * 16777216) + (string.byte(rx_body, 8) * 65536) + (string.byte(rx_body, 9) * 256) + string.byte(rx_body, 10)
  elseif dp_type == 0x04 then
    data_value = string.byte(rx_body, 7)
  end

  log.info(string.format("📡 [수신] 기기: %s | DP_ID: %d | Type: %d | Value: %d", device.manufacturer, dp_id, dp_type, data_value))

  local profile = DEVICE_PROFILES[device.manufacturer]

  if profile then
    local parser_func = profile[dp_id]
    if parser_func then
      parser_func(device, data_value)
    else
      local unknown_log = string.format("DP:%d=Val:%d", dp_id, data_value)
      log.warn("⚠️ 미등록 데이터 포착: " .. unknown_log)
      device:emit_event(capabilities.firmwareUpdate.currentVersion({value = unknown_log}))
    end
  else
    log.warn("⚠️ 사전에 등록되지 않은 기기입니다: " .. tostring(device.manufacturer))
  end
end

-- ====================================================================
-- 4. 드라이버 실행
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
  zigbee_handlers = {
    cluster = {
      [TUYA_CLUSTER] = {
        [0x01] = tuya_handler,
        [0x02] = tuya_handler,
        [0x24] = tuya_handler
      }
    }
  },
})

log.info("🚀 AD Tuya 통합 드라이버 (구조화 버전) 실행 완료!")
tuya_driver:run()