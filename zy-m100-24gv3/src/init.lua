local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local log = require "log"
local my_tuya_utils = require "tuya_utils" -- 기존 커스텀 유틸 유지

local TUYA_CLUSTER = my_tuya_utils.CLUSTER_ID or 0xEF00
local RADAR_CAP_ID = "voicewatch56866.radarDistance"

-- ====================================================================
-- 🎮 1. 커맨드 핸들러 (앱 조작 -> 기기 송신)
-- ====================================================================
local capability_handlers = {
  [RADAR_CAP_ID] = {
    setDistanceSwitch = function(driver, device, command)
      local send_val = (command.args.value == "on") and 1 or 0
      my_tuya_utils.send_command(device, 101, my_tuya_utils.types.BOOL, send_val)
    end,
    setDetectionDistanceMin = function(driver, device, command)
      local send_val = math.floor((command.args.value * 100) + 0.5)
      my_tuya_utils.send_command(device, 3, my_tuya_utils.types.VALUE, send_val)
    end,
    setDetectionDistanceMax = function(driver, device, command)
      local send_val = math.floor((command.args.value * 100) + 0.5)
      my_tuya_utils.send_command(device, 4, my_tuya_utils.types.VALUE, send_val)
    end,
    setMoveSensitivity = function(driver, device, command)
      my_tuya_utils.send_command(device, 2, my_tuya_utils.types.VALUE, command.args.value)
    end,
    setPresenceSensitivity = function(driver, device, command)
      my_tuya_utils.send_command(device, 102, my_tuya_utils.types.VALUE, command.args.value)
    end,
    setPresenceTimeout = function(driver, device, command)
      my_tuya_utils.send_command(device, 105, my_tuya_utils.types.VALUE, command.args.value)
    end
  }
}

-- ====================================================================
-- 📡 2. 데이터 처리 핸들러 (기기 보고 -> 앱 화면 갱신)
-- ====================================================================
local function handle_radar_data(device, dp_id, value)
  local cap = capabilities[RADAR_CAP_ID]

  if dp_id == 1 then -- 존재 여부 (표준 역량)
    local state = (value == 1 or value == 2) and "present" or "not present"
    device:emit_event(capabilities.presenceSensor.presence(state))
  elseif dp_id == 103 then -- 조도 (표준 역량)
    device:emit_event(capabilities.illuminanceMeasurement.illuminance({value = value}))
  elseif dp_id == 9 then -- 현재 거리 (0.1m 단위)
    device:emit_event(cap.distance({ value = value / 10.0, unit = "m" }))
  elseif dp_id == 3 then -- 최소 거리
    device:emit_event(cap.detectionDistanceMin({ value = value / 100.0, unit = "m" }))
  elseif dp_id == 4 then -- 최대 거리
    device:emit_event(cap.detectionDistanceMax({ value = value / 100.0, unit = "m" }))
  elseif dp_id == 101 then -- 스위치
    device:emit_event(cap.distanceSwitch(value == 1 and "on" or "off"))
  elseif dp_id == 2 then -- 동작 민감도
    device:emit_event(cap.moveSensitivity(value))
  elseif dp_id == 102 then -- 재실 민감도
    device:emit_event(cap.presenceSensitivity(value))
  elseif dp_id == 105 then -- 유지 시간
    device:emit_event(cap.presenceTimeout(value))
  end
end

-- ====================================================================
-- 📡 3. Tuya 로우 데이터 파서
-- ====================================================================
local function tuya_handler(driver, device, zb_rx)
  local rx_body = zb_rx.body.zcl_body.body_bytes
  if #rx_body < 6 then return end

  local dp_id = string.byte(rx_body, 3)
  local dp_type = string.byte(rx_body, 4)
  local data_len = (string.byte(rx_body, 5) * 256) + string.byte(rx_body, 6)

  local data_value = 0
  if dp_type == my_tuya_utils.types.BOOL or dp_type == my_tuya_utils.types.ENUM then
    data_value = string.byte(rx_body, 7)
  elseif dp_type == my_tuya_utils.types.VALUE and data_len == 4 then
    data_value = (string.byte(rx_body, 7) * 16777216) + (string.byte(rx_body, 8) * 65536) + (string.byte(rx_body, 9) * 256) + string.byte(rx_body, 10)
  end

  handle_radar_data(device, dp_id, data_value)
  log.info(string.format("📡 [수신] DP:%d | Type:%d | Value:%d", dp_id, dp_type, data_value))
end

-- ====================================================================
-- 🔍 4. 상태 동기화 및 라이프사이클
-- ====================================================================
local function query_device_status(device)
  log.info("🔍 [동기화] 기기 상태 요청 (Query 0x00)")

  my_tuya_utils.send_query(device)
end

local function device_init(driver, device)
  log.info("==================================================")
  log.info("🟢 기기 로드 완료: " .. (device.label or device.device_network_id))

  -- 역량 확인 로직 유지
  if device.profile and device.profile.components then
    for comp_id, component in pairs(device.profile.components) do
      for cap_id, _ in pairs(component.capabilities or {}) do
        log.info(string.format("   ✔️ [%s] %s", comp_id, cap_id))
      end
    end
  end
  log.info("==================================================")

  query_device_status(device)
end

-- ====================================================================
-- 🚀 5. 드라이버 실행부
-- ====================================================================
local tuya_driver = ZigbeeDriver("zy-m100-24gv3", {
  supported_capabilities = {
    capabilities.presenceSensor,
    capabilities.illuminanceMeasurement,
    capabilities[RADAR_CAP_ID],
  },
  lifecycle_handlers = {
    init = device_init,
    added = function(driver, device)
      log.info("🎉 새 기기 추가됨")
      query_device_status(device)
    end
  },
  capability_handlers = capability_handlers,
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

tuya_driver:run()