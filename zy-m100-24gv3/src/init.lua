local ZigbeeDriver = require "st.zigbee"
local capabilities = require "st.capabilities"
local log = require "log"
local tuya_utils = require "tuya_utils" -- 🌟 여기서 한 번만 부릅니다.

local utils = require "st.utils" -- 👈 테이블 시각화를 위한 라이브러리

-- 테이블 인덱스 에러 방지를 위해 로컬 상수로 다시 정의하거나
-- 하단 테이블에서 tuya_utils.CLUSTER_ID를 직접 사용해야 합니다.
local TUYA_CLUSTER = tuya_utils.CLUSTER_ID or 0xEF00

local RADAR_CAP_ID = "voicewatch56866.radarInfo"

-- ====================================================================
-- 🌟 전송 래퍼 함수 (init.lua 내부에서 사용)
-- ====================================================================
local function send_tuya_command(device, dp_id, dp_type, value)
  tuya_utils.send_command(device, dp_id, dp_type, value)
  log.info(string.format("🚀 [공식 유틸 송신] DP:%d | Type:%02X | Value:%s", dp_id, dp_type, tostring(value)))
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
}

-- ====================================================================
-- 🛡️ [공식 API 기반] 객체 타입 전용 표준 송신 함수
-- ====================================================================
local function safe_emit_custom_event(device, cap_id, attr_id, value)
  -- 1. 메인 컴포넌트 객체를 가져옵니다.
  local component = device.profile.components.main

  -- 2. 사용자님의 Schema 규격 { "value": "string" } 에 맞춘 순수 데이터 생성
  -- 다른 메타데이터가 섞이지 않도록 'Clean Table'을 만듭니다.
  local clean_payload = { value = tostring(value) }

  -- 3. [공식 정석 API] emit_component_event 사용
  -- 이 API는 emit_event보다 데이터 검증 시 유연하며,
  -- 특히 객체(Object) 형태의 속성을 보낼 때 SDK 문서에서 권장하는 방식입니다.
  if component then
    device:emit_component_event(component, cap_id, attr_id, clean_payload)
    log.info(string.format("✅ [표준 송신] %s -> %s", attr_id, tostring(value)))
  else
    log.error("❌ [오류] 컴포넌트를 찾을 수 없습니다.")
  end
end

-- ====================================================================
-- 🛡️ [정석 방식] 스마트싱스 SDK 표준 규격 준수 송신 함수
-- ====================================================================
local function safe_emit_custom_event(device, cap_id, attr_id, value)
  local cap = capabilities[cap_id]
  if not cap then return end

  -- 1. 속성 객체(Attribute Object)를 가져옵니다.
  local attr_obj = cap[attr_id]
  if not attr_obj then return end

  -- [중요] SDK 내부 라이브러리(aware.lua)의 충돌을 막기 위해
  -- NAME 필드가 없을 경우 수동으로 채워줍니다. (표준 규격 보완)
  if type(attr_obj) == "table" and not attr_obj.NAME then
    attr_obj.NAME = attr_id
  end

  -- 2. 사용자님의 JSON 설계도(type: object)에 맞는 데이터 덩어리를 만듭니다.
  -- 설계도에서 { "value": { "type": "string" } } 로 정의했으므로 아래 구조가 '객체 값'이 됩니다.
  local object_value = { value = value }

  -- 3. [정석의 핵심] SDK가 제공하는 생성자 함수를 사용하여 'Event' 객체를 만듭니다.
  -- 만약 attr_obj가 함수라면 실행하고, 아니라면 표준 테이블 구조를 반환합니다.
  local event
  if type(attr_obj) == "function" then
    -- SDK가 정상적으로 함수를 생성한 경우
    event = attr_obj(object_value)
  else
    -- SDK가 함수화하지 못한 경우, 수동으로 표준 이벤트 테이블 조립
    event = {
      capability = cap,
      attribute = attr_obj,
      state = { value = object_value } -- 🌟 JSON 객체 타입에 맞춘 매핑
    }
  end

  -- 4. 생성된 정석 이벤트 객체를 송신합니다.
  if event then
    device:emit_event(event)
    log.info(string.format("✅ [정석 송신] %s -> %s", attr_id, tostring(value)))
  end
end

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
  if device:supports_capability_by_id(RADAR_CAP_ID) then
    local custom_cap = capabilities[RADAR_CAP_ID]
    local display_text = ""

    if value == 0 then
      display_text = "감지 안 됨 (0 cm)"
    else
      display_text = string.format("%.2f m", value / 10.0)
    end

	safe_emit_custom_event(device, RADAR_CAP_ID, "distance", display_text)
  end

  return true
end

-- ====================================================================
-- 🛡️ [최종] 타입 대응 정밀 송신 함수 (Table/Function 모두 지원)
-- ====================================================================
-- local function safe_emit_custom_event(device, cap_id, attr_id, value)
--   local cap = capabilities[cap_id]

--   -- [관문 1] 역량 존재 확인
--   if not cap then
--     log.warn(string.format("⚠️ [1단계 실패] '%s' 역량 로드 불가", cap_id))
--     return
--   end

--   -- [관문 2] 속성 존재 확인
--   local attr = cap[attr_id]
--   if not attr then
--     log.warn(string.format("⚠️ [2단계 실패] '%s' 역량 내 '%s' 속성 없음", cap_id, attr_id))
--     return
--   end

--   -- [관문 3] 실행 방식 결정
--   local attr_type = type(attr)

--   if attr_type == "function" then
--     -- 케이스 A: 정석적인 함수형 (직접 실행)
--     device:emit_event(attr({value = value}))
--     log.info(string.format("✅ [송신:Function] %s -> %s", attr_id, tostring(value)))

--   elseif attr_type == "table" then
--     -- 케이스 B: 테이블형 (구조체를 직접 조립하여 송신)
--     -- 스마트싱스 내부에서 테이블일 경우, 해당 속성 객체 자체가 이벤트를 생성할 수 있습니다.
--     local event = {
--       capability = cap,
--       attribute = attr,
--       state = { value = value }
--     }
--     device:emit_event(event)
--     log.info(string.format("✅ [송신:Table] %s -> %s", attr_id, tostring(value)))

--   else
--     log.warn(string.format("⚠️ [3단계 실패] '%s'의 타입이 예상 밖입니다: %s", attr_id, attr_type))
--   end
-- end

-- ====================================================================
-- 3. 기기별 DP 매핑 사전
-- ====================================================================
local DEVICE_PROFILES = {
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
      local state = (value == 1 or value == true) and "On" or "Off"
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
    presenceTimeout      = { dp = 105, type = tuya_utils.types.VALUE, factor = 1 },
    presenceSensitivity  = { dp = 102, type = tuya_utils.types.VALUE, factor = 1 },
    moveSensitivity      = { dp = 2,   type = tuya_utils.types.VALUE, factor = 1 },
    detectionDistanceMin = { dp = 3,   type = tuya_utils.types.VALUE, factor = 100 },
    detectionDistanceMax = { dp = 4,   type = tuya_utils.types.VALUE, factor = 100 },
    distanceSwitch       = { dp = 101, type = tuya_utils.types.BOOL,  factor = 1 }
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
      tuya_utils.send_command(device, cfg.dp, cfg.type, send_val)
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
local tuya_driver = ZigbeeDriver("zy-m100-24gv3", {
  supported_capabilities = {
    capabilities.presenceSensor,
    capabilities.illuminanceMeasurement,
	capabilities[RADAR_CAP_ID],
  },
  lifecycle_handlers = {
	init = device_init, -- 🌟 기기 초기화 감지기 등록
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

log.info("🚀  Tuya ZY-M100-24GV3 드라이버 실행!")
tuya_driver:run()