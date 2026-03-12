    {
        fingerprint: tuya.fingerprint("TS0601", [
            "_TZE200_yjjdcqsq",
            "_TZE284_9yapgbuv",
            "_TZE200_9yapgbuv",
            "_TZE200_utkemkbs",
            "_TZE204_utkemkbs",
            "_TZE284_utkemkbs",
            "_TZE204_9yapgbuv",
            "_TZE204_upagmta9",
            "_TZE200_cirvgep4",
            "_TZE204_d7lpruvi",
            "_TZE200_upagmta9",
            "_TZE204_yjjdcqsq",
            "_TZE204_jygvp6fk",
            "_TZE204_cirvgep4",
            "_TZE284_yjjdcqsq",
            "_TZE200_d7lpruvi",
            "_TZE284_hdyjyqjm",
            "_TZE284_d7lpruvi",
            "_TZE284_upagmta9",
            "_TZE204_ksz749x8",
            "_TZE204_1wnh8bqp",
            "_TZE284_1wnh8bqp",
        ]),
        model: "TS0601_temperature_humidity_sensor_2",
        vendor: "Tuya",
        description: "Temperature and humidity sensor",
        extend: [
            tuya.modernExtend.tuyaBase({
                dp: true,
                queryOnDeviceAnnounce: true,
                queryOnConfigure: true,
                respondToMcuVersionResponse: true,
                timeStart: "1970",
            }),
        ],
        exposes: [e.temperature(), e.humidity(), tuya.exposes.batteryState(), tuya.exposes.temperatureUnit()],
        meta: {
            tuyaDatapoints: [
                [1, "temperature", tuya.valueConverter.divideBy10],
                [2, "humidity", tuya.valueConverter.raw],
                [3, "battery_state", tuya.valueConverter.batteryState],
                [9, "temperature_unit", tuya.valueConverter.temperatureUnitEnum],
            ],
        },
        whiteLabel: [
            tuya.whitelabel("Tuya", "ZTH01", "Temperature and humidity sensor", ["_TZE200_yjjdcqsq", "_TZE204_yjjdcqsq", "_TZE284_yjjdcqsq"]),
            tuya.whitelabel("Tuya", "SZTH02", "Temperature and humidity sensor", ["_TZE200_utkemkbs", "_TZE204_utkemkbs", "_TZE284_utkemkbs"]),
            tuya.whitelabel("Tuya", "ZTH02", "Temperature and humidity sensor", ["_TZE200_9yapgbuv", "_TZE204_9yapgbuv"]),
            tuya.whitelabel("Tuya", "ZTH05", "Temperature and humidity sensor", ["_TZE204_upagmta9", "_TZE200_upagmta9", "_TZE284_upagmta9"]),
            tuya.whitelabel("Tuya", "ZTH08-E", "Temperature and humidity sensor", ["_TZE200_cirvgep4", "_TZE204_cirvgep4"]),
            tuya.whitelabel("Tuya", "ZTH08", "Temperature and humidity sensor", ["_TZE204_d7lpruvi", "_TZE284_d7lpruvi", "_TZE284_hdyjyqjm"]),
        ],
    },
    {
        fingerprint: tuya.fingerprint("TS0601", ["_TZE200_vvmbj46n", "_TZE284_vvmbj46n", "_TZE200_w6n8jeuu", "_TZE284_cwyqwqbf"]),
        model: "ZTH05Z",
        vendor: "Tuya",
        description: "Temperature and humidity sensor",
        extend: [
            tuya.modernExtend.tuyaBase({
                dp: true,
                queryOnDeviceAnnounce: true,
                queryOnConfigure: true,
                respondToMcuVersionResponse: true,
                timeStart: "1970",
            }),
        ],
        exposes: (device, options) => {
            const exps: Expose[] = [
                e.temperature(),
                e.humidity(),
                e.enum("temperature_unit", ea.STATE_SET, ["celsius", "fahrenheit"]).withDescription("Temperature unit"),
                e
                    .numeric("max_temperature_alarm", ea.STATE_SET)
                    .withUnit("°C")
                    .withValueMin(-20)
                    .withValueMax(60)
                    .withDescription("Alarm temperature max"),
                e
                    .numeric("min_temperature_alarm", ea.STATE_SET)
                    .withUnit("°C")
                    .withValueMin(-20)
                    .withValueMax(60)
                    .withDescription("Alarm temperature min"),
                e.numeric("max_humidity_alarm", ea.STATE_SET).withUnit("%").withValueMin(0).withValueMax(100).withDescription("Alarm humidity max"),
                e.numeric("min_humidity_alarm", ea.STATE_SET).withUnit("%").withValueMin(0).withValueMax(100).withDescription("Alarm humidity min"),
                e.enum("temperature_alarm", ea.STATE, ["lower_alarm", "upper_alarm", "cancel"]).withDescription("Temperature alarm"),
                e.enum("humidity_alarm", ea.STATE, ["lower_alarm", "upper_alarm", "cancel"]).withDescription("Humidity alarm"),
                e
                    .numeric("temperature_periodic_report", ea.STATE_SET)
                    .withUnit("min")
                    .withValueMin(1)
                    .withValueMax(120)
                    .withDescription("Temp periodic report"),
                e
                    .numeric("humidity_periodic_report", ea.STATE_SET)
                    .withUnit("min")
                    .withValueMin(1)
                    .withValueMax(120)
                    .withDescription("Humidity periodic report"),
                e
                    .numeric("temperature_sensitivity", ea.STATE_SET)
                    .withUnit("°C")
                    .withValueMin(0.3)
                    .withValueMax(1)
                    .withValueStep(0.1)
                    .withDescription("Sensitivity of temperature"),
                e
                    .numeric("humidity_sensitivity", ea.STATE_SET)
                    .withUnit("%")
                    .withValueMin(3)
                    .withValueMax(10)
                    .withValueStep(1)
                    .withDescription("Sensitivity of humidity"),
            ];

            if (device && device.manufacturerName === "_TZE284_cwyqwqbf") {
                exps.push(tuya.exposes.batteryState());
            } else {
                exps.push(e.battery());
            }

            return exps;
        },
        meta: {
            tuyaDatapoints: [
                [1, "temperature", tuya.valueConverter.divideBy10],
                [2, "humidity", tuya.valueConverter.raw],
                [3, "battery_state", tuya.valueConverter.batteryState],
                [4, "battery", tuya.valueConverter.raw],
                [9, "temperature_unit", tuya.valueConverter.temperatureUnitEnum],
                [10, "max_temperature_alarm", tuya.valueConverter.divideBy10],
                [11, "min_temperature_alarm", tuya.valueConverter.divideBy10],
                [12, "max_humidity_alarm", tuya.valueConverter.raw],
                [13, "min_humidity_alarm", tuya.valueConverter.raw],
                [
                    14,
                    "temperature_alarm",
                    tuya.valueConverterBasic.lookup({
                        lower_alarm: tuya.enum(0),
                        upper_alarm: tuya.enum(1),
                        cancel: tuya.enum(2),
                    }),
                ],
                [
                    15,
                    "humidity_alarm",
                    tuya.valueConverterBasic.lookup({
                        lower_alarm: tuya.enum(0),
                        upper_alarm: tuya.enum(1),
                        cancel: tuya.enum(2),
                    }),
                ],
                [17, "temperature_periodic_report", tuya.valueConverter.raw],
                [18, "humidity_periodic_report", tuya.valueConverter.raw],
                [19, "temperature_sensitivity", tuya.valueConverter.divideBy10],
                [20, "humidity_sensitivity", tuya.valueConverter.raw],
            ],
        },
        whiteLabel: [
            tuya.whitelabel("ONENUO", "TH05Z", "Temperature & humidity sensor with clock and humidity display", ["_TZE200_vvmbj46n"]),
            tuya.whitelabel("Tuya", "TZE284_cwyqwqbf", "Temperature & humidity sensor with LCD clock", ["_TZE284_cwyqwqbf"]),
        ],
    },