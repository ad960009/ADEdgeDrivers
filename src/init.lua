local ZigbeeDriver = require "st.zigbee"
local log = require "log"

-- 기기가 처음 연결(초기화)될 때 실행될 함수
local function device_init(driver, device)
  log.info("🎉 기기가 허브에 연결 및 초기화되었습니다: " .. device.id)
end

-- 드라이버 뼈대 생성
local tuya_driver = ZigbeeDriver("my_tuya_driver", {
  supported_capabilities = {},
  lifecycle_handlers = {
    init = device_init
  }
})

-- 허브에 드라이버가 올라갈 때 찍히는 로그
log.info("🚀 나의 첫 번째 지그비 드라이버가 실행되었습니다!")

-- 드라이버 구동 시작
tuya_driver:run()