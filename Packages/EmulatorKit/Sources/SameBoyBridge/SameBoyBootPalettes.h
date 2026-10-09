/*
Expat License

Copyright (c) 2015-2026 Lior Halphon

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

#pragma once

#include <stdint.h>

// RGB555 data and combination indices from the pinned SameBoy BootROMs/cgb_boot.asm.
// Pan Docs Power_Up_Sequence.md: compatibility uses BG0, OBJ0 and OBJ1, indexed by BGP/OBP.
static const uint16_t sb_boot_palette_colors[][4] = {
    [0]  = {0x7fff, 0x32bf, 0x00d0, 0x0000},
    [1]  = {0x639f, 0x4279, 0x15b0, 0x04cb},
    [2]  = {0x7fff, 0x6e31, 0x454a, 0x0000},
    [3]  = {0x7fff, 0x1bef, 0x0200, 0x0000},
    [4]  = {0x7fff, 0x421f, 0x1cf2, 0x0000},
    [5]  = {0x7fff, 0x5294, 0x294a, 0x0000},
    [6]  = {0x7fff, 0x03ff, 0x012f, 0x0000},
    [12] = {0x53ff, 0x4a5f, 0x7e52, 0x0000},
    [18] = {0x7fff, 0x03ea, 0x011f, 0x0000},
    [24] = {0x7fff, 0x03ff, 0x001f, 0x0000},
    [27] = {0x0000, 0x4200, 0x037f, 0x7fff},
    [28] = {0x7fff, 0x7e8c, 0x7c00, 0x0000},
    [29] = {0x7fff, 0x1bef, 0x6180, 0x0000},
};

// BG, OBJ0, OBJ1. Table order matches the bridge's twelve boot palette enum cases.
static const uint8_t sb_boot_palette_combinations[][3] = {
    {0, 0, 0},    // Up
    {4, 3, 28},   // Up + A
    {1, 0, 0},    // Up + B
    {12, 12, 12}, // Down
    {24, 24, 24}, // Down + A
    {6, 28, 3},   // Down + B
    {28, 4, 3},   // Left
    {2, 4, 0},    // Left + A
    {5, 5, 5},    // Left + B
    {18, 18, 18}, // Right
    {29, 4, 4},   // Right + A
    {27, 27, 27}, // Right + B
};
