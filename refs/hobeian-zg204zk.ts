    {
        zigbeeModel: ["ZG-204ZK"],
        fingerprint: tuya.fingerprint("TS0601", ["_TZE200_ka8l86iu", "_TZE200_zbfmvj13"]),
        model: "ZG-204ZK",
        vendor: "HOBEIAN",
        description: "24Ghz human presence sensor",
        extend: [tuya.modernExtend.tuyaBase({dp: true})],
        exposes: [
            e.presence(),
            e.battery(),
            e
                .numeric("fading_time", ea.STATE_SET)
                .withValueMin(0)
                .withValueMax(28800)
                .withValueStep(1)
                .withUnit("s")
                .withDescription("Presence keep time"),
            e
                .numeric("static_detection_distance", ea.STATE_SET)
                .withValueMin(0)
                .withValueMax(5)
                .withValueStep(0.01)
                .withUnit("m")
                .withDescription("Static detection distance"),
            e
                .numeric("static_detection_sensitivity", ea.STATE_SET)
                .withValueMin(0)
                .withValueMax(10)
                .withValueStep(1)
                .withUnit("x")
                .withDescription("Static detection sensitivity"),
            e
                .numeric("motion_detection_sensitivity", ea.STATE_SET)
                .withValueMin(0)
                .withValueMax(10)
                .withValueStep(1)
                .withUnit("x")
                .withDescription("Motion detection sensitivity (Firmware version>=0122052017)"),
            e.binary("indicator", ea.STATE_SET, "ON", "OFF").withDescription("LED indicator mode"),
        ],
        meta: {
            tuyaDatapoints: [
                [1, "presence", tuya.valueConverter.trueFalse1],
                [102, "fading_time", tuya.valueConverter.raw],
                [4, "static_detection_distance", tuya.valueConverter.divideBy100],
                [2, "static_detection_sensitivity", tuya.valueConverter.raw],
                [107, "indicator", tuya.valueConverter.onOff],
                [123, "motion_detection_sensitivity", tuya.valueConverter.raw],
                [121, "battery", tuya.valueConverter.raw],
                [106, "illuminance", tuya.valueConverter.raw],
            ],
        },
    },