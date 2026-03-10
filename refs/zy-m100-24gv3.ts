    {
        fingerprint: tuya.fingerprint("TS0601", ["_TZE204_ya4ft0w4", "_TZE200_ya4ft0w4", "_TZE204_gkfbdvyx", "_TZE200_gkfbdvyx"]),
        model: "ZY-M100-24GV3",
        vendor: "Tuya",
        description: "24G MmWave radar human presence motion sensor (added distance switch)",
        extend: [tuya.modernExtend.tuyaBase({dp: true})],
        exposes: (device, options) => {
            const exps = [
                e.enum("state", ea.STATE, ["none", "presence", "move"]).withDescription("Presence state sensor"),
                e.presence().withDescription("Occupancy"),
                e.numeric("distance", ea.STATE).withUnit("m").withDescription("Target distance"),
                e.binary("find_switch", ea.STATE_SET, "ON", "OFF").withDescription("distance switch"),
                e.illuminance().withDescription("Illuminance sensor"),
                e.numeric("move_sensitivity", ea.STATE_SET).withValueMin(1).withValueMax(10).withValueStep(1).withDescription("Motion Sensitivity"),
                e
                    .numeric("presence_sensitivity", ea.STATE_SET)
                    .withValueMin(1)
                    .withValueMax(10)
                    .withValueStep(1)
                    .withDescription("Presence Sensitivity"),
                e
                    .numeric("presence_timeout", ea.STATE_SET)
                    .withValueMin(1)
                    .withValueMax(15000)
                    .withValueStep(1)
                    .withUnit("s")
                    .withDescription("Fade time"),
            ];
            if (!device || device.manufacturerName === "_TZE204_gkfbdvyx" || device.manufacturerName === "_TZE200_gkfbdvyx") {
                exps.push(
                    e
                        .numeric("detection_distance_min", ea.STATE_SET)
                        .withValueMin(0)
                        .withValueMax(6)
                        .withValueStep(0.5)
                        .withUnit("m")
                        .withDescription("Minimum range"),
                );
                exps.push(
                    e
                        .numeric("detection_distance_max", ea.STATE_SET)
                        .withValueMin(0.5)
                        .withValueMax(9.0)
                        .withValueStep(0.5)
                        .withUnit("m")
                        .withDescription("Maximum range"),
                );
            } else {
                exps.push(
                    e
                        .numeric("detection_distance_min", ea.STATE_SET)
                        .withValueMin(0)
                        .withValueMax(8.25)
                        .withValueStep(0.75)
                        .withUnit("m")
                        .withDescription("Minimum range"),
                );
                exps.push(
                    e
                        .numeric("detection_distance_max", ea.STATE_SET)
                        .withValueMin(0.75)
                        .withValueMax(9.0)
                        .withValueStep(0.75)
                        .withUnit("m")
                        .withDescription("Maximum range"),
                );
            }
            return exps;
        },
        meta: {
            tuyaDatapoints: [
                [
                    1,
                    null,
                    {
                        from: (v: number, meta: Fz.Meta) => {
                            if (v === 0) {
                                return {
                                    state: "none",
                                    presence: false,
                                };
                            }
                            if (v === 1) {
                                return {
                                    state: "presence",
                                    presence: true,
                                };
                            }
                            if (v === 2) {
                                return {
                                    state: "move",
                                    presence: true,
                                };
                            }
                            return {
                                state: "none",
                                presence: false,
                            };
                        },
                    },
                ],
                [2, "move_sensitivity", tuya.valueConverter.raw],
                [3, "detection_distance_min", tuya.valueConverter.divideBy100],
                [4, "detection_distance_max", tuya.valueConverter.divideBy100],
                [9, "distance", tuya.valueConverter.divideBy10],
                [101, "find_switch", tuya.valueConverter.onOff],
                [102, "presence_sensitivity", tuya.valueConverter.raw],
                [103, "illuminance", tuya.valueConverter.raw],
                [105, "presence_timeout", tuya.valueConverter.raw],
            ],
        },
    },