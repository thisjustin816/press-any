// Port of gbtoolsid's src/sig_music.c and sig_soundfx.c.

private typealias D = GBToolsIDData

extension GBToolsIDEngine {
    // MARK: sig_music.c

    func checkMusic() {
        var entry = formatEntry(.music, "GHX", "")
        if findPatternStrNoTerm(D.sig_str_ghx_audio) || findPatternStrNoTerm(D.sig_str_ghx_sound) {
            entryAdd(entry)
        }

        if findPatternStrNoTerm(D.sig_str_devsound_classic) {
            entry = formatEntry(.music, "DevSound", "Classic")
            entryAdd(entry)
        } else if findPatternStrNoTerm(D.sig_str_devsound_lite) {
            entry = formatEntry(.music, "DevSound", "Lite")
            entryAdd(entry)
        } else if findPatternStrNoTerm(D.sig_str_devsound_x) {
            entry = formatEntry(.music, "DevSound", "X")
            entryAdd(entry)
        } else if findPatternStrNoTerm(D.sig_str_devsound_x2) {
            entry = formatEntry(.music, "DevSound", "X2")
            entryAdd(entry)
        } else if findPatternStrNoTerm(D.sig_str_dev_GBMod) {
            entry = formatEntry(.music, "GBMod", "")
            entryAdd(entry)
        }

        if findPatternStrNoTerm(D.sig_str_gbmusicplayer_audio) {
            entry = formatEntry(.music, "Visual Impact", "")
            entryAdd(entry)
        }

        if findPatternStrNoTerm(D.sig_str_MusyX_1)
            || findPatternStrNoTerm(D.sig_str_MusyX_2)
            || findPatternStrNoTerm(D.sig_str_MusyX_3) {
            entry = formatEntry(.music, "MusyX", "")
            entryAdd(entry)
        }

        if findPatternStrNoTerm(D.sig_str_freaq_1) || findPatternStrNoTerm(D.sig_str_freaq_2) {
            entry = formatEntry(.music, "Freaq", "")
            entryAdd(entry)
        }

        entry = formatEntry(.music, "LSDJ", "")
        if findPatternStrNoTerm(D.sig_str_lsdj_1) || findPatternStrNoTerm(D.sig_str_lsdj_2) {
            entryAdd(entry)
        } else if checkPatternAtAddr(D.sig_lsdpack_header_title, D.sig_lsdpack_header_title_at_0x134) {
            entryAdd(entry)
        }

        // hUGETracker and variants
        entry = formatEntry(.music, "hUGETracker", "SuperDisk")
        if findPatternBuf(D.sig_hugetracker_fx_vol_slide_base_v1) {
            entryAdd(entry)
        } else if findPatternBuf(D.sig_hugetracker_fx_vol_slide_base_v2) {
            entryAdd(entry)
        } else if findPatternBuf(D.sig_hugetracker_fortissimo_fx_vol_slide) {
            entry = formatEntry(.music, "hUGETracker", "fortISSimO")
            entryAdd(entry)
        } else if findPatternBuf(D.sig_hugetracker_fx_get_note_poly) {
            if findPatternBuf(D.sig_hugetracker_fx_coffeebat_get_shift_ch3) {
                entry = formatEntry(.music, "hUGETracker", "Coffee Bat")
                entryAdd(entry)
            } else {
                entryAdd(entry) // Fallback, default hUGETracker entry
            }
        }

        if findPatternStrNoTerm(D.sig_tbengine_noisetable) {
            entry = formatEntry(.music, "Trackerboy engine", "")
            entryAdd(entry)
        }

        if findPatternBuf(D.sig_blackboxplayer_1) && findPatternBuf(D.sig_blackboxplayer_2) {
            entry = formatEntry(.music, "Black Box Music Box", "")
            entryAdd(entry)
        }

        if findPatternBuf(D.sig_lemon_wave_default) {
            entry = formatEntry(.music, "Lemon", "")
            entryAdd(entry)
        }

        if findPatternBuf(D.sig_gbtplayer_gbt_wave) {
            entry = formatEntry(.music, "GBT Player", "")
            entryAdd(entry)
        }

        entry = formatEntry(.music, "Carillon Player", "Standard")
        if findPatternStrNoTerm(D.sig_carillon_player_1) || findPatternStrNoTerm(D.sig_carillon_player_2) {
            entryAdd(entry)
        } else if findPatternBuf(D.sig_carillon_player_3) {
            if findPatternBuf(D.sig_makrillon_1) {
                entry = formatEntry(.music, "Carillon Player", "Makrillon")
                entryAdd(entry)
            } else {
                entryAdd(entry)
            }
        }

        entry = formatEntry(.music, "MPlay", "")
        if findPatternBuf(D.sig_mplay2) {
            entryAddWithVersion(entry, "2")
        } else if findPatternBuf(D.sig_mplay1) {
            entryAddWithVersion(entry, "1")
        }

        // GBSoundSystem (Paragon5) and variants
        entry = formatEntry(.music, "GBSoundSystem", "Modern")
        if findPatternBuf(D.sig_bin_gbsoundsystem_modern_SSFP_multi_sfx) {
            entryAdd(entry)
        } else {
            entry = formatEntry(.music, "GBSoundSystem", "Classic")
            if findPatternStrNoTerm(D.sig_str_gbsoundsystem_1) && findPatternStrNoTerm(D.sig_str_gbsoundsystem_2) {
                entryAdd(entry)
            } else if findPatternBuf(D.sig_bin_gbsoundsystem_MultiSFXLoop) {
                entryAdd(entry)
            }
        }

        // MMLGB and variants
        if findPatternBuf(D.sig_mmlgb1) || findPatternBuf(D.sig_mmlgb2) {
            entry = formatEntry(.music, "MMLGB", "")

            if findPatternBuf(D.sig_mmlgb_v2) {
                entryAddWithVersion(entry, "Retro-Hax")
            } else {
                entryAdd(entry)
            }
        }

        // GBMC (Game Boy Music Compiler)
        if findPatternBuf(D.sig_gbmc_snd_exec_modv) {
            entry = formatEntry(.music, "GBMC", "")
            entryAdd(entry)
        }

        // QuickThunder (Audio Arts). A byte buffer searched with the NOTERM macro, so gbtoolsid
        // drops its last byte; findPatternStrNoTerm does the same.
        if findPatternStrNoTerm(D.sig_quickthunder_audio_arts_ch2) {
            entry = formatEntry(.music, "QuickThunder", "")
            entryAdd(entry)
        }

        if findPatternBuf(D.sig_imedgboy) {
            entry = formatEntry(.music, "IMEDGBoy", "")
            entryAdd(entry)
        }

        if findPatternBuf(D.sig_cosmigo3) {
            entry = formatEntry(.music, "Cosmigo", "")
            entryAdd(entry)
        }

        if checkPatternAtAddr(D.sig_deflemask_romstart, D.sig_deflemask_at_0x0001) {
            entry = formatEntry(.music, "DefleMask", "")
            entryAdd(entry)
        }

        if findPatternStrNoTerm(D.sig_tonicfur) {
            entry = formatEntry(.music, "TonicFur Audio Engine", "")
            entryAdd(entry)
        }
    }

    // MARK: sig_soundfx.c

    func checkSoundFX() {
        var entry = formatEntry(.soundfx, "FX Hammer", "")
        if findPatternStrNoTerm(D.sig_fxhammer_info_1) || findPatternStrNoTerm(D.sig_fxhammer_info_2) {
            entryAdd(entry)
        }

        entry = formatEntry(.soundfx, "CBT-FX", "")
        if findPatternStrNoTerm(D.sig_cbtfx_info) {
            entryAdd(entry)
        }

        entry = formatEntry(.soundfx, "VAL-FX", "")
        if findPatternStrNoTerm(D.sig_valfx_info) {
            entryAdd(entry)
        }

        entry = formatEntry(.soundfx, "DevSFX", "")
        if findPatternStrNoTerm(D.sig_str_DevSFX) {
            entryAdd(entry)
        }

        entry = formatEntry(.soundfx, "VGM2GBSFX", "")
        if findPatternBuf(D.sig_vgm2gbsfx_aud3waveram_load) || findPatternBuf(D.sig_vgm2gbsfx_aud3waveram_load_v2) {
            entryAdd(entry)
        }
    }
}
