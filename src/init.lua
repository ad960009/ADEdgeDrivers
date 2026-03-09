local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local log = require "log"

-- Tuya 전용 클러스터 번호
local TUYA_CLUSTER = 0xEF00

-- 기기가 처음 연결될 때
local function device_init(driver, device)
  log.info("🎉 HOBEIAN 기기 연결됨: " .. device.id)
end

-- 🌟 Tuya 0xEF00 클러스터 메시지를 가로채서 해독하는 함수 🌟
local function tuya_handler(driver, device, zb_rx)
  local rx_body = zb_rx.body.zcl_body.body_bytes

  -- Tuya Payload 기본 구조: [상태 1byte] [시퀀스 1byte] [DP_ID 1byte] [타입 1byte] [길이 2byte] [데이터...]
  if #rx_body < 6 then return end

  local dp_id = string.byte(rx_body, 3)
  local dp_type = string.byte(rx_body, 4)
  local data_length = (string.byte(rx_body, 5) * 256) + string.byte(rx_body, 6)

  -- 데이터 추출 (Bool 또는 숫자값)
  local data_value = 0
  if dp_type == 0x01 then -- Boolean 타입 (재실 유무 등)
    data_value = string.byte(rx_body, 7)
  elseif dp_type == 0x02 and data_length == 4 then -- Value 타입 (숫자)
    data_value = (string.byte(rx_body, 7) * 16777216) + (string.byte(rx_body, 8) * 65536) + (string.byte(rx_body, 9) * 256) + string.byte(rx_body, 10)
  end

  -- 로그 출력 (퇴근 후 이 로그를 보면서 dp_id를 매핑하면 됩니다!)
  log.info(string.format("📡 [Tuya 데이터 수신] DP_ID: %d | Type: %d | Value: %d", dp_id, dp_type, data_value))

  -- 임시 로직: 만약 DP_ID가 1번이고(보통 Tuya 재실센서는 1번을 씁니다), 그 값이 1(True)라면 스위치를 켠다!
  if dp_id == 1 then
    if data_value == 1 then
      device:emit_event(capabilities.switch.switch.on())
      log.info("🏃 재실 감지됨! (스위치 ON)")
    else
      device:emit_event(capabilities.switch.switch.off())
      log.info("텅~ 비었음! (스위치 OFF)")
    end
  end
end

-- 드라이버 뼈대 생성 및 핸들러 등록
local tuya_driver = ZigbeeDriver("hobeian_tuya_driver", {
  supported_capabilities = {
    capabilities.switch
  },
  lifecycle_handlers = {
    init = device_init
  },
  zigbee_handlers = {
    cluster = {
      [TUYA_CLUSTER] = {
        [0x01] = tuya_handler, -- Tuya Command 0x01 매핑
        [0x02] = tuya_handler  -- Tuya Command 0x02 매핑
      }
    }
  }
})

log.info("🚀 HOBEIAN ZG-204ZK 드라이버 실행 완료!")
tuya_driver:run()