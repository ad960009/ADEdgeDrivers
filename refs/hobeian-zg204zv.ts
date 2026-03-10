    {
        zigbeeModel: ["ZG-204ZV"],
        fingerprint: tuya.fingerprint("TS0601", ["_TZE200_uli8wasj", "_TZE200_grgol3xp", "_TZE200_rhgsbacq", "_TZE200_y8jijhba"]),
        model: "ZG-204ZV",
        vendor: "HOBEIAN",
        description: "Millimeter wave motion detection",
        extend: [tuya.modernExtend.tuyaBase({dp: true})],
        exposes: [
            e.presence(),
            e.illuminance(),
            e.temperature(),
            e.humidity(),
            tuya.exposes.temperatureUnit(),
            tuya.exposes.temperatureCalibration(),
            tuya.exposes.humidityCalibration(),
            e.battery(),
            e
                .numeric("fading_time", ea.STATE_SET)
                .withValueMin(0)
                .withValueMax(28800)
                .withValueStep(1)
                .withUnit("s")
                .withDescription("Motion keep time"),
            e.binary("indicator", ea.STATE_SET, "ON", "OFF").withDescription("LED indicator mode"),
            e
                .numeric("illuminance_interval", ea.STATE_SET)
                .withValueMin(1)
                .withValueMax(720)
                .withValueStep(1)
                .withUnit("minutes")
                .withDescription("Light sensing sampling(refresh and update only while active)"),
            e
                .numeric("motion_detection_sensitivity", ea.STATE_SET)
                .withValueMin(0)
                .withValueMax(19)
                .withValueStep(1)
                .withUnit("x")
                .withDescription("The larger the value, the more sensitive it is (refresh and update only while active)"),
        ],
        meta: {
            tuyaDatapoints: [
                [1, "presence", tuya.valueConverter.trueFalse1],
                [106, "illuminance", tuya.valueConverter.raw],
                [102, "fading_time", tuya.valueConverter.raw],
                [2, "motion_detection_sensitivity", tuya.valueConverter.raw],
                [108, "indicator", tuya.valueConverter.onOff],
                [110, "battery", tuya.valueConverter.raw],
                [111, "temperature", tuya.valueConverter.divideBy10],
                [101, "humidity", tuya.valueConverter.raw],
                [109, "temperature_unit", tuya.valueConverter.temperatureUnit],
                [105, "temperature_calibration", tuya.valueConverter.localTempCalibration3],
                [104, "humidity_calibration", tuya.valueConverter.localTempCalibration2],
                [107, "illuminance_interval", tuya.valueConverter.raw],
            ],
        },
    },