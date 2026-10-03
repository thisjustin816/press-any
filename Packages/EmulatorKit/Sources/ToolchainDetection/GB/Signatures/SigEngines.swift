// Port of gbtoolsid's src/sig_zgb.c, sig_crosszgb.c, sig_gbbasic.c and sig_gbstudio.c.

private typealias D = GBToolsIDData

extension GBToolsIDEngine {
    // MARK: sig_zgb.c

    func checkZGB() -> Bool {
        let entry = formatEntry(.engine, "ZGB", "")

        // Require sound const pattern, as starting filter
        if findPatternBuf(D.sig_zgb_sound) {
            if findPatternBuf(D.sig_zgb_2017) {
                entryAddWithVersion(entry, "2016-2017")
                return true
            }

            // ZGB 2020.0
            if findPatternBuf(D.sig_zgb_2020_0_pushbank) && findPatternBuf(D.sig_zgb_2020_0_popbank) {
                entryAddWithVersion(entry, "2020.0")
                return true
            }
        }

        // ZGB 2020.1
        if findPatternBuf(D.sig_zgb_2020_1_plus_pushbank) && findPatternBuf(D.sig_zgb_2020_1_plus_popbank) {
            if findPatternBuf(D.sig_zgb_2020_1_settile) {
                entryAddWithVersion(entry, "2020.1")
                return true
            } else if findPatternBuf(D.sig_zgb_2020_2_plus_settile) {
                // v2020.2: GBDK 2.x - GBDK-2020 3.2.0
                if checkPatternAtAddr(D.sig_zgb_gbdk_bmp, D.sig_zgb_gbdk_bmp_2x_to_2020_320_at) {
                    entryAddWithVersion(entry, "2020.2")
                    return true
                }

                // 2021.0
                if findPatternBuf(D.sig_zgb_2021_0_flushoamsprite) {
                    entryAddWithVersion(entry, "2021.0")
                    return true
                } else {
                    // 2021.2+
                    if findPatternBuf(D.sig_zgb_2021_2_plus_update_attr) {
                        if entryCheckMatch(.tools, D.STR_GBDK, D.STR_GBDK_2020_4_0_5_v0_zgb)
                            || entryCheckMatch(.tools, D.STR_GBDK, D.STR_GBDK_2020_4_0_5_v1_retracted) {
                            entryAddWithVersion(entry, "2021.2 - 2021.3")
                            return true
                        }
                        // 2022.0 uses GBDK 4.1.0
                        if entryCheckMatch(.tools, D.STR_GBDK, D.STR_GBDK_2020_4_1_0_to_4_1_1) {
                            entryAddWithVersion(entry, "2022.0+")
                            return true
                        }
                        // 2023.0 uses GBDK 4.2.0
                        if entryCheckMatch(.tools, D.STR_GBDK, D.STR_GBDK_2020_4_2_0) {
                            entryAddWithVersion(entry, "2023.0+")
                            return true
                        }
                    }
                    // 2021.1
                    else if entryCheckMatch(.tools, D.STR_GBDK, D.STR_GBDK_2020_4_0_5_v0_zgb) {
                        entryAddWithVersion(entry, "2021.1")
                        return true
                    }

                    // ZGB 2020.2+, version unclear
                    entryAddWithVersion(entry, "Unknown")
                    return true
                }
            }
        }

        return false
    }

    // MARK: sig_crosszgb.c

    func checkCrossZGB() -> Bool {
        let entry = formatEntry(.engine, "Cross ZGB", "")

        // ZGB 2025.0
        if findPatternBuf(D.sig_crosszgb_buffer_exchange_v2025_0) {
            entryAddWithVersion(entry, "2025.0")
            return true
        }

        return false
    }

    // MARK: sig_gbbasic.c

    func checkGBBasic() -> Bool {
        if checkPatternAtAddr(D.sig_gbbasic_magic_v11, D.sig_gbbasic_magic_v11_at) {
            entryAdd(formatEntry(.engine, "GBBasic", "v1.1"))
            return true
        } else if checkPatternAtAddr(D.sig_gbbasic_actor_init_alpha, D.sig_gbbasic_actor_init_alpha3_at) {
            entryAdd(formatEntry(.engine, "GBBasic", "Alpha3"))
            return true
        } else if checkPatternAtAddr(D.sig_gbbasic_actor_init_alpha, D.sig_gbbasic_actor_init_alpha4_at) {
            entryAdd(formatEntry(.engine, "GBBasic", "Alpha4"))
            return true
        }

        return false
    }

    // MARK: sig_gbstudio.c

    func checkGBStudio() -> Bool {
        let entry = formatEntry(.engine, "GBStudio", "")

        // GBStudio 1.0.0 - 1.2.1
        if findPatternBuf(D.sig_gbs_fades_1_0_0_to_1_2_2) {
            if findPatternBuf(D.sig_gbs_uicolors_1_0_0) {
                entryAddWithVersion(entry, "1.0.0")
                return true
            } else if findPatternBuf(D.sig_gbs_uicolors_1_1_0_plus) {
                entryAddWithVersion(entry, "1.0.0 - 1.2.2")
                return true
            }
        }
        // GBStudio 2.0.0 beta 1 (only checked if the previous test fails)
        else if findPatternBuf(D.sig_gbs_fades_2_0_0_beta1) {
            entryAddWithVersion(entry, "2.0.0 Beta 1")
            return true
        }

        // GBStudio 2.0.0 beta 2+
        if findPatternBuf(D.sig_gbs_fades_2_0_0_beta2_plus) {
            if findPatternBuf(D.sig_gbs_uicolors_2_0_0_beta5_plus) {
                entryAddWithVersion(entry, "2.0.0 beta 5+")
                return true
            } else {
                entryAddWithVersion(entry, "2.0.0 beta 2 - 4")
                return true
            }
        }

        // GBStudio 3.0.0+
        if findPatternBuf(D.sig_gbs_math_c_sinetable_3_0_0_alpha1_plus)
            || findPatternBuf(D.sig_gbs_vm_c_vm_step_3_0_0_alpha1_plus) {
            if findPatternBuf(D.sig_gbs_fade_manager_c_dmgfadetowhitestep_2_0_0_b5_to_3_1_0) {
                if findPatternBuf(D.sig_gbs_musicmanager_c_FX_ADDR_LO__2_0_0_b5_to_3_0_3) {
                    // GBStudio 3.0.0 alpha 1+ uses GBDK 4.0.4
                    if entryCheckMatch(.tools, D.STR_GBDK, D.STR_GBDK_2020_4_0_4) {
                        entryAddWithVersion(entry, "3.0.0 alpha 1+")
                        return true
                    }
                    // GBStudio 3.0.0 - 3.1.0+ uses GBDK 4.0.5 and 4.0.6
                    else if entryCheckMatch(.tools, D.STR_GBDK, D.STR_GBDK_2020_4_0_5_to_4_0_6) {
                        entryAddWithVersion(entry, "3.0.0 - 3.0.3")
                        return true
                    }
                } else {
                    entryAddWithVersion(entry, "3.1.0")
                    return true
                }
            }
            // GBStudio 3.2.0 uses an interim build between GBDK 4.2.0 and 4.3.0
            else if entryCheckMatch(.tools, D.STR_GBDK, D.STR_GBDK_2020_4_3_0_plus) {
                if findPatternBufMasked(D.sig_gbs_vminstruct_4_0_0_plus) {
                    if findPatternBufMasked(D.sig_gbs_iotafmt_4_2_0_plus) {
                        entryAddWithVersion(entry, "4.1.0+")
                        return true
                    }

                    entryAddWithVersion(entry, "4.0.0 - 4.0.2")
                    return true
                }

                entryAddWithVersion(entry, "3.2.0 - 3.2.1")
                return true
            }
        }

        return false
    }
}
