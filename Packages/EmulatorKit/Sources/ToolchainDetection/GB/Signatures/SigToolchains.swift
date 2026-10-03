// Port of gbtoolsid's src/sig_gbdk.c, sig_turborascal.c, sig_gbforth.c, sig_gbnim.c,
// sig_gbsdk.c, sig_matlabgb.c and sig_llvmgb_libgbxx.c.

private typealias D = GBToolsIDData

extension GBToolsIDEngine {
    // MARK: sig_gbdk.c

    func checkGBDK() -> Bool {
        let entry = formatEntry(.tools, D.STR_GBDK, "")

        // GBDK-2020 4.0.0
        if checkPatternAtAddr(D.sig_gbdk_0x80_GBDK_4_0_0, D.sig_gbdk_0x80_at) {
            // Additional test to strengthen match
            if checkPatternAtAddr(D.sig_gbdk_0x20_GBDK_2020_400_0x20, D.sig_gbdk_0x20_at) {
                entryAddWithVersion(entry, D.STR_GBDK_2020_4_0_0)
                return true
            }
        }

        // GBDK 2.x - GBDK-2020 3.2.0
        if checkPatternAtAddr(D.sig_gbdk_bmp, D.sig_gbdk_bmp_2x_to_2020_320_at) {
            // GBDK-2020 3.2.0
            if checkPatternAtAddr(D.sig_gbdk_0x164_GBDK_320, D.sig_gbdk_0x164_GBDK_320_at) {
                entryAddWithVersion(entry, D.STR_GBDK_2020_3_2_0)
                return true
            }

            // GBDK 2.9.0 - GBDK-2020 3.1.0
            if checkPatternAtAddr(D.sig_gbdk_0x1c2_GBDK_29x, D.sig_gbdk_0x1c2_GBDK_29x_at) {
                // GBDK 2.9.5 - GBDK-2020 3.1.0
                if checkPatternAtAddr(D.sig_gbdk_0x1ca_GBDK_295, D.sig_gbdk_0x1ca_GBDK_295_at) {
                    entryAddWithVersion(entry, D.STR_GBDK_2_9_5_to_2020_3_1_0)
                    return true
                }

                // GBDK 2.9.0 - GBDK 2.9.4
                entryAddWithVersion(entry, D.STR_GBDK_2_9_0_to_2_9_4)
                return true
            }

            // GBDK 2.0.18 - GBDK 2.1.5
            if checkPatternAtAddr(D.sig_gbdk_0x1c2_GBDK_2018_to_215, D.sig_gbdk_0x1c2_GBDK_2018_to_215_at) {
                entryAddWithVersion(entry, D.STR_GBDK_2_0_18_to_2_1_5)
                return true
            }

            // GBDK 2.0.x - GBDK 2.0.17
            if checkPatternAtAddr(D.sig_gbdk_0x1c2_GBDK_20x_to_2017, D.sig_gbdk_0x1c2_GBDK_20x_to_2017_at) {
                entryAddWithVersion(entry, D.STR_GBDK_2_0_x_to_2_0_17)
                return true
            }

            // GBDK 2.x, cannot narrow down further
            entryAddWithVersion(entry, D.STR_GBDK_2_x)
            return true
        }

        // GBDK-2020 4.0.1 and later
        if checkPatternAtAddr(D.sig_gbdk_0x20_GBDK_2020_401_plus_0x20, D.sig_gbdk_0x20_at)
            && checkPatternAtAddr(D.sig_gbdk_0x20_GBDK_2020_401_plus_0x28, D.sig_gbdk_0x28_at) {
            // Additional test to strengthen match
            if checkPatternAtAddr(D.sig_gbdk_0x30_GBDK_2020_401_plus, D.sig_gbdk_0x30_at) {
                // GBDK-2020 4.0.1 - 4.0.2
                if checkPatternAtAddr(D.sig_gbdk_0x150, D.sig_gbdk_0x150_GBDK_2020_401_to_402_at) {
                    entryAddWithVersion(entry, D.STR_GBDK_2020_4_0_1_to_4_0_2)
                    return true
                }

                // GBDK-2020 4.0.3 - 4.0.4
                if checkPatternAtAddr(D.sig_gbdk_0x153_GBDK_2020_403_plus, D.sig_gbdk_0x153_GBDK_2020_403_plus_at) {
                    // GBDK-2020 4.0.4 and later
                    if checkPatternAtAddr(D.sig_gbdk_0x100_GBDK_4_0_4, D.sig_gbdk_0x100_at) {
                        entryAddWithVersion(entry, D.STR_GBDK_2020_4_0_4)
                        return true
                    }

                    entryAddWithVersion(entry, D.STR_GBDK_2020_4_0_3)
                    return true
                }

                // 4.0.5+
                if checkPatternAtAddr(D.sig_gbdk_0x157_GBDK_2020_405_plus, D.sig_gbdk_0x157_GBDK_2020_405_plus_at) {
                    // 4.0.5.v1 was retracted and replaced after two months
                    if checkPatternAtAddr(D.sig_gbdk_clear_WRAM_tail_GBDK_2020_405_v1, D.sig_gbdk_clear_WRAM_tail_GBDK_2020_405_v1_at) {
                        entryAddWithVersion(entry, D.STR_GBDK_2020_4_0_5_v1_retracted)
                        return true
                    }
                    // Standard 4.0.5 cannot be distinguished from 4.0.6 by crt0.s
                    else if checkPatternAtAddr(D.sig_gbdk_clear_WRAM_tail_GBDK_2020_405_v2_to_406, D.sig_gbdk_clear_WRAM_tail_GBDK_2020_405_v2_to_406_at) {
                        entryAddWithVersion(entry, D.STR_GBDK_2020_4_0_5_to_4_0_6)
                        return true
                    }
                    // 4.1.0+
                    else if checkPatternAtAddr(D.sig_gbdk_clear_WRAM_tail_GBDK_2020_410_plus, D.sig_gbdk_clear_WRAM_tail_GBDK_2020_410_plus_at) {
                        if checkPatternAtAddr(D.sig_gbdk_0xCC_GBDK_4_2_0_vsync, D.sig_gbdk_0xCC_at) {
                            entryAddWithVersion(entry, D.STR_GBDK_2020_4_2_0_interim)
                        } else {
                            entryAddWithVersion(entry, D.STR_GBDK_2020_4_1_0_to_4_1_1)
                        }

                        return true
                    }
                    // 4.2.0+
                    else if checkPatternAtAddr(D.sig_gbdk_clear_WRAM_tail_GBDK_2020_420, D.sig_gbdk_clear_WRAM_tail_GBDK_2020_420_at) {
                        // 4.3.0+
                        if checkPatternAtAddr(D.sig_gbdk_clear_WRAM_tail_GBDK_2020_430_plus, D.sig_gbdk_clear_WRAM_tail_GBDK_2020_430_plus_at) {
                            entryAddWithVersion(entry, D.STR_GBDK_2020_4_3_0_plus)
                            return true
                        }

                        entryAddWithVersion(entry, D.STR_GBDK_2020_4_2_0)
                        return true
                    }
                    // Some ZGB versions use a GBDK between 4.0.4 and 4.0.5.v1
                    else if checkPatternAtAddr(D.sig_gbdk_0x100_GBDK_4_0_5_v0_zgb, D.sig_gbdk_0x100_at) {
                        entryAddWithVersion(entry, D.STR_GBDK_2020_4_0_5_v0_zgb)
                        return true
                    }
                }

                // GBDK 4.x, version unclear. gbtoolsid adds this entry and then falls through
                // without returning.
                entryAddWithVersion(entry, D.STR_GBDK_2020_4_UNKNOWN)
            }
        }

        // GBDK 1.x - 2.0.x
        if checkPatternAtAddr(D.sig_gbdk_0x150_GBDK_1_x, D.sig_gbdk_0x150_GBDK_1_x_at)
            && checkPatternAtAddr(D.sig_gbdk_0x158_GBDK_1_x, D.sig_gbdk_0x158_GBDK_1_x_at) {
            entryAddWithVersion(entry, D.STR_GBDK_1_x_to_2_0_x)
            return true
        }

        return false
    }

    // MARK: sig_turborascal.c

    func checkTurboRascal() {
        // Declared inline in the C source. sizeof() of the string includes its terminator, so
        // the check covers "TRSE GB" plus a NUL byte.
        let sig_turborascal_header_at = 0x0134
        let sig_turborascal_header: [UInt8] = Array("TRSE GB".utf8) + [0]

        let entry = formatEntry(.tools, "Turbo Rascal Syntax Error", "")
        if checkPatternAtAddr(sig_turborascal_header, name: "sig_turborascal_header", sig_turborascal_header_at) {
            entryAdd(entry)
        }
    }

    // MARK: sig_gbforth.c

    func checkGBForth() {
        let entry = formatEntry(.tools, "GBForth", "")
        if findPatternBuf(D.sig_gbforth_startup_1) {
            // Gap of one byte, then next pattern
            if checkPatternAtAddr(D.sig_gbforth_startup_2, getAddrLastMatch() + D.sig_gbforth_startup_1_next_at) {
                // Gap of one byte, then next pattern
                if checkPatternAtAddr(D.sig_gbforth_startup_3, getAddrLastMatch() + D.sig_gbforth_startup_2_next_at) {
                    entryAdd(entry)
                }
            }
        }
    }

    // MARK: sig_gbnim.c

    func checkGBNim() {
        let entry = formatEntry(.tools, "gbnim", "")
        if checkPatternAtAddr(D.sig_gbnim_startup_1, D.sig_gbnim_startup_1_at) {
            if checkPatternAtAddr(D.sig_gbnim_startup_2, D.sig_gbnim_startup_2_at) {
                entryAdd(entry)
            }
        } else if findPatternStrNoTerm(D.sig_gbnim_exception_handle_string) {
            entryAdd(entry)
        }
    }

    // MARK: sig_gbsdk.c

    func checkGBSDK() {
        let entry = formatEntry(.tools, "gbsdk", "")
        if findPatternBuf(D.sig_gbsdk_joypad) {
            entryAdd(entry)
        }
    }

    // MARK: sig_matlabgb.c

    func checkMatlabGB() {
        let entry = formatEntry(.tools, "Matlab GB", "")
        if checkPatternAtAddr(D.sig_matlabgb_setup_gameboy_gfx, D.sig_matlabgb_setup_gameboy_gfx_at) {
            entryAdd(entry)
        } else if checkPatternAtAddr(D.sig_matlabgb_update_audio_reg, D.sig_matlabgb_update_audio_reg_at) {
            entryAdd(entry)
        }

        // Not an else: gbtoolsid can add this entry a second time.
        if findPatternBufMasked(D.sig_matlabgb_turn_off_screen) {
            entryAdd(entry)
        }
    }

    // MARK: sig_llvmgb_libgbxx.c

    func checkLLVMGBLibGBXX() {
        let entry = formatEntry(.tools, "libgb++", "")
        if findPatternBufMasked(D.sig_llvmgb_libgbxx_runtime_startup) {
            entryAdd(entry)
        }
    }
}
