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
-- 🛡️ [최종] 문자열 기반 커스텀 이벤트 직접 송신 함수
-- ====================================================================
local function safe_emit_custom_event(device, cap_id, attr_id, value)
  -- 1. 값을 반드시 문자열로 변환 (이중 포장 제거)
  local string_value = tostring(value)

  -- 2. 역량 로드 확인
  local cap_obj = capabilities[cap_id]
  if not cap_obj then
    log.error(string.format("❌ '%s' 역량을 찾을 수 없습니다.", cap_id))
    return
  end

  local attr_obj = cap_obj[attr_id]

  -- 3. 송신 로직 실행
  if type(attr_obj) == "function" then
    -- 혹시라도 함수로 정상 로드된 경우
    device:emit_event(attr_obj(string_value))
    log.info(string.format("✅ [송신:F] %s -> %s", attr_id, string_value))
  else
    -- 함수가 아닌 원시 테이블로 로드된 경우 (현재 상황)
    -- 객체 참조 대신 안전하게 명시적 문자열 ID를 사용하여 송신
    device:emit_event({
      component_id = "main",  -- 컴포넌트 명시
      capability_id = cap_id, -- 예: "voicewatch56866.radarInfo"
      attribute_id = attr_id, -- 예: "distance"
      state = { value = string_value } -- 🌟 이중 포장 해제! 순수 문자열만 전달
    })
    log.info(string.format("✅ [송신:T] %s -> %s", attr_id, string_value))
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