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
      -- 참고: 1(존재)과 2(움직임)를 앱에 다르게 띄우려면 커스텀 capability가 필요하므로 일단 present로 통일합니다.
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
  end
}

-- ====================================================================
-- 2. 기기별 DP 매핑 사전 (여기에 기기 정보를 계속 추가하면 됩니다!)
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
    [1]   = parsers.presence_complex, -- 상태가 0, 1, 2로 들어옴
    [103] = parsers.illuminance
    -- (거리, 민감도 등은 나중에 preference로 제어하기 위해 일단 정보 표시용만 등록)
  }
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
  elseif dp_type == 0x04 then -- Enum 타입 (ZY-M100의 상태값 등에 사용됨)
    data_value = string.byte(rx_body, 7)
  end

  log.info(string.format("📡 [수신] 기기: %s | DP_ID: %d | Type: %d | Value: %d", device.manufacturer, dp_id, dp_type, data_value))

  -- 사전에서 이 기기의 제조사 코드를 찾음
  local profile = DEVICE_PROFILES[device.manufacturer]

  if profile then
    -- 사전에서 DP_ID에 해당하는 파싱 함수를 찾음
    local parser_func = profile[dp_id]
    if parser_func then
      -- 함수 실행!
      parser_func(device, data_value)
    else
      log.warn("⚠️ 이 기기(DP: " .. dp_id .. ")의 처리 방법이 정의되지 않았습니다.")
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
    capabilities.relativeHumidityMeasurement
  },
  zigbee_handlers = {
    cluster = {
      [TUYA_CLUSTER] = {
        [0x01] = tuya_handler,
        [0x02] = tuya_handler,
        [0x24] = tuya_handler
      }
    }
  }
})

log.info("🚀 AD Tuya 통합 드라이버 (구조화 버전) 실행 완료!")
tuya_driver:run()