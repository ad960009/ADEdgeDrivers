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
local ZG204ZV_CAP_ID = "voicewatch56866.hobeianZg204zv"

-- ====================================================================
-- 🌟 전송 래퍼 함수 (init.lua 내부에서 사용) - 음수 처리 패치 완료!
-- ====================================================================
local function send_tuya_command(device, dp_id, dp_type, value)
  local send_value = value

  -- VALUE 타입(숫자)이면서 음수일 경우, 32비트 Unsigned(2의 보수) 형태로 강제 변환합니다.
  if dp_type == tuya_utils.types.VALUE and type(value) == "number" and value < 0 then
    send_value = value & 0xFFFFFFFF
  end

  tuya_utils.send_command(device, dp_id, dp_type, send_value)

  local device_name = device.label or device.device_network_id or "Unknown"
  log.info(string.format("[%s] 🚀 DP:%d | Type:%02X | Value:%s (Converted: %s)", device_name, dp_id, dp_type, tostring(value), tostring(send_value)))
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
  },
  [ZG204ZV_CAP_ID] = {
    setIndicator = function(driver, device, command)
      local send_val = (command.args.value == "on") and 1 or 0
      send_tuya_command(device, 108, tuya_utils.types.BOOL, send_val)
    end,
    setMotionSensitivity = function(driver, device, command)
      send_tuya_command(device, 2, tuya_utils.types.VALUE, command.args.value)
    end,
    setFadingTime = function(driver, device, command)
      send_tuya_command(device, 102, tuya_utils.types.VALUE, command.args.value)
    end,
    setIlluminanceInterval = function(driver, device, command)
      send_tuya_command(device, 107, tuya_utils.types.VALUE, command.args.value)
    end,
    -- setTempCalibration = function(driver, device, command)
    --   -- UI에서 -1.5 등 소수점 입력 시 10배 곱해서 -15로 전송 (음수 오버플로우는 send_tuya_command에서 처리됨)
    --   local send_val = math.floor((command.args.value * 10) + 0.5)
    --   if command.args.value < 0 then
    --     send_val = math.ceil((command.args.value * 10) - 0.5) -- 음수 반올림 보정
    --   end
    --   send_tuya_command(device, 105, tuya_utils.types.VALUE, send_val)
    -- end,
    -- setHumidCalibration = function(driver, device, command)
    --   local send_val = math.floor(command.args.value + 0.5)
    --   if command.args.value < 0 then
    --     send_val = math.ceil(command.args.value - 0.5) -- 음수 반올림 보정
    --   end
    --   send_tuya_command(device, 104, tuya_utils.types.VALUE, send_val)
    -- end
  }
}

-- ====================================================================
-- 📡 2. 파싱 함수 및 DP 매핑 사전 (Device -> UI)
-- ====================================================================
local parsers = {
  -- [공통 파서 (presence_complex, illuminance, temperature, humidity, battery 등)는 그대로 유지]
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

  -- 🌟 [ZG-204ZK 전용 파서]
  hobeian_indicator_zk = function(device, value)
    local state = (value == 1 or value == true) and "on" or "off"
    device:emit_event(capabilities[ZG204ZK_CAP_ID].indicator(state))
  end,
  hobeian_static_dist_zk = function(device, value)
    device:emit_event(capabilities[ZG204ZK_CAP_ID].staticDetectionDistance(value / 100.0))
  end,
  hobeian_static_sens_zk = function(device, value)
    device:emit_event(capabilities[ZG204ZK_CAP_ID].staticDetectionSensitivity(value))
  end,
  hobeian_motion_sens_zk = function(device, value)
    device:emit_event(capabilities[ZG204ZK_CAP_ID].motionDetectionSensitivity(value))
  end,
  hobeian_fading_time_zk = function(device, value)
    device:emit_event(capabilities[ZG204ZK_CAP_ID].fadingTime(value))
  end, -- 👈 콤마 잊지 않기!

  -- 🌟 [ZG-204ZV 전용 파서]
  hobeian_indicator_zv = function(device, value)
    local state = (value == 1 or value == true) and "on" or "off"
    device:emit_event(capabilities[ZG204ZV_CAP_ID].indicator(state))
  end,
  hobeian_motion_sens_zv = function(device, value)
    device:emit_event(capabilities[ZG204ZV_CAP_ID].motionSensitivity(value))
  end,
  hobeian_fading_time_zv = function(device, value)
    device:emit_event(capabilities[ZG204ZV_CAP_ID].fadingTime(value))
  end,
  hobeian_illum_interval_zv = function(device, value)
    device:emit_event(capabilities[ZG204ZV_CAP_ID].illuminanceInterval(value))
  end,
  hobeian_temp_calib_zv = function(device, value)
    -- 기기에서 온 음수(2의 보수)를 다시 마이너스 숫자로 변환 후 UI로 표시
    local signed_val = value
    if value > 0x7FFFFFFF then signed_val = value - 0x100000000 end
    -- device:emit_event(capabilities[ZG204ZV_CAP_ID].tempCalibration(signed_val / 10.0))
    log.info(string.format("[%s] 🌡️ (설정) 온도 보정값 확인: %.1f", device.label, signed_val/10.0))
  end,
  hobeian_humid_calib_zv = function(device, value)
    -- 습도 보정도 동일하게 음수 변환 후 UI 표시
    local signed_val = value
    if value > 0x7FFFFFFF then signed_val = value - 0x100000000 end
    -- device:emit_event(capabilities[ZG204ZV_CAP_ID].humidCalibration(signed_val))
    log.info(string.format("[%s] 💧 (설정) 습도 보정값 확인: %.1f", device.label, signed_val))

  end,
  hobeian_temp_unit_zv = function(device, value)
    -- UI 속성엔 없지만, 혹시 날아올 경우를 대비해 로그만 남김
    log.info(string.format("[%s] 🌡️ 온도 단위 수신: %d", device.label, value))
  end,
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
  [107] = { func = parsers.hobeian_indicator_zk },
  [4]   = { func = parsers.hobeian_static_dist_zk },
  [2]   = { func = parsers.hobeian_static_sens_zk },
  [123] = { func = parsers.hobeian_motion_sens_zk },
  [102] = { func = parsers.hobeian_fading_time_zk },
}

local ZG204ZV_MAP = {
  [1]   = { func = parsers.presence_complex },
  [106] = { func = parsers.illuminance, factor = 1.0 },
  [111] = { func = parsers.temperature, factor = 10.0 }, -- 투야 온도는 보통 10
  [101] = { func = parsers.humidity, factor = 1.0 },     -- 투야 습도는 보통 1
  [110] = { func = parsers.battery },

  [102] = { func = parsers.hobeian_fading_time_zv },
  [2] = { func = parsers.hobeian_static_sens_zv },
  [108] = { func = parsers.hobeian_indicator_zv }, -- indicator
  [109] = { func = parsers.hobeian_temp_unit_zv }, -- temp unit
  [105] = { func = parsers.hobeian_temp_calib_zv }, -- temp calibration
  [104] = { func = parsers.hobeian_humid_calib_zv }, -- humid calibration
  [107] = { func = parsers.hobeian_illum_interval_zv }, -- illuminance interval
}

local DEVICE_PROFILES = {
  ["HOBEIAN"] = ZG204ZK_MAP,
  ["_TZE200_rhgsbacq"] = ZG204ZV_MAP,
  ["_TZE284_rhgsbacq"] = ZG204ZV_MAP,
  ["_TZE200_9n8j6l7g"] = ZG204ZV_MAP,
  ["_TZE284_9n8j6l7g"] = ZG204ZV_MAP,

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
  log.info("📋 [현재 기기 프로필에 등록된 역량 및 캐시된 멤버 확인]")

  local has_caps = false

  -- 스마트싱스 기기 객체의 프로필 > 컴포넌트 > 역량 구조를 순회합니다.
  if device.profile and device.profile.components then
    for comp_id, component in pairs(device.profile.components) do
      for cap_id, _ in pairs(component.capabilities or {}) do
        log.info(string.format("   ✔️ [%s] %s", comp_id, cap_id))
        has_caps = true

        -- 🌟 캐시 상태 확인용: 역량 객체 내부 멤버(속성/명령어) 출력
        local cap_def = capabilities[cap_id]
        if cap_def then
          local members = {}
          for key, val in pairs(cap_def) do
            -- 내부 메타데이터(대문자 등)나 숨겨진 속성 제외하고 실제 멤버만 추출
            if type(key) == "string" and not key:match("^_") and key ~= "ID" and key ~= "VERSION" and key ~= "NAME" then
              table.insert(members, key)
            end
          end

          if #members > 0 then
            table.sort(members)
            log.info(string.format("      ↳ 로드된 멤버: %s", table.concat(members, ", ")))
          else
            log.info("      ↳ 로드된 멤버: (없음 또는 시스템 기본 역량)")
          end
        else
          log.warn("      ↳ ⚠️ 주의: 허브 캐시에 이 역량 정의가 아직 없습니다!")
        end
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
        if val < 0 then
          send_val = math.ceil((val * cfg.factor) - 0.5) -- 음수 반올림 안전 보정
        end
      end

      log.info(string.format("⚙️ [설정 변경 송신] %s -> %d(%d) (DP: %d)", name, send_val, val, cfg.dp))
      send_tuya_command(device, cfg.dp, cfg.type, send_val)
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
    capabilities[ZG204ZV_CAP_ID],
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