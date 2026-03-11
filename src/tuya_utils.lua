local messages = require "st.zigbee.messages"
local zcl_messages = require "st.zigbee.zcl"
local data_types = require "st.zigbee.data_types"
local generic_body = require "st.zigbee.generic_body"
local zb_const = require "st.zigbee.constants" -- 🌟 모범 답안의 핵심: 공식 상수 라이브러리

local tuya_utils = {}

tuya_utils.types = {
  BOOL    = 0x01,
  VALUE   = 0x02,
  STRING  = 0x03,
  ENUM    = 0x04,
}

tuya_utils.CLUSTER_ID = 0xEF00

function tuya_utils.send_command(device, dp_id, dp_type, value)
  -- 1️⃣ 데이터 타입별 패킹 (기존의 안전한 방식 유지)
  local dp_data = ""
  if dp_type == tuya_utils.types.BOOL then
    dp_data = string.pack(">I1", value)
  elseif dp_type == tuya_utils.types.VALUE then
    dp_data = string.pack(">I4", value)
  elseif dp_type == tuya_utils.types.ENUM then
    dp_data = string.pack(">I1", value)
  end

  -- 2️⃣ Payload Body 조립 (모범 답안 구조 적용)
  local packet_id = 0x0000
  local dp_data_len = string.len(dp_data)
  -- 문자열 병합 오류를 막기 위해 완벽한 바이트 패킹 적용
  local payload_str = string.pack(">I2 I1 I1 I2", packet_id, dp_id, dp_type, dp_data_len) .. dp_data
  local payload_body = generic_body.GenericBody(payload_str)

  -- 3️⃣ 🌟 모범 답안의 핵심 1: ZclHeader 객체 제어
  -- cmd만 넣고 생성한 뒤, 내부 내장 함수로 비트를 조작합니다! (타입 에러 원천 차단)
  local zclh = zcl_messages.ZclHeader({cmd = data_types.ZCLCommandId(0x00)})
  zclh.frame_ctrl:set_cluster_specific()
  zclh.frame_ctrl:set_disable_default_response()

  -- 4️⃣ 🌟 모범 답안의 핵심 2: AddressHeader 상수 사용
  -- 엔드포인트를 하드코딩하지 않고 기기 정보에서 가져옵니다.
  local endpoint = device:get_endpoint(tuya_utils.CLUSTER_ID) or 0x01
  local addrh = messages.AddressHeader(
    zb_const.HUB.ADDR,            -- 허브 주소 (0x0000)
    zb_const.HUB.ENDPOINT,        -- 허브 엔드포인트 (0x01)
    device:get_short_address(),   -- 기기 주소
    endpoint,                     -- 기기 엔드포인트
    zb_const.HA_PROFILE_ID,       -- 프로필 (0x0104)
    tuya_utils.CLUSTER_ID         -- 클러스터 (0xEF00)
  )

  -- 5️⃣ 최종 메시지 조립 및 전송
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = payload_body
  })

  local msg = messages.ZigbeeMessageTx({
    address_header = addrh,
    body = message_body
  })

  device:send(msg)
end

return tuya_utils