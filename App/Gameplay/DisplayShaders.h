// Display treatments that work in linear light. The renderer binds sRGB views of the frames for
// these modes, so every sample arrives linear and only the result is encoded. Frame blending
// therefore mixes light, as a slow screen does.
//
// SameBoy LCD: Lior Halphon, Expat. Authentic GBC geometry: fishku, CC0. The Monochrome LCD is
// this app's own code, drawing BGB's measured screen colors.
// GBA and SP101 color profiles: Pokefan531 and hunterk, public domain. The CRT is this app's own
// code, modelled on CRT-Lottes by Timothy Lottes (public domain). Sources, pinned revisions and
// bundled notices are in THIRD_PARTY_NOTICES.md.
#pragma once

float3 linearToSRGB(float3 c) {
    c = saturate(c);
    return select(1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, c * 12.92, c <= 0.0031308);
}

// Column-major sRGB matrices and luminance from the upstream profiles.
float3 gbaProfile(float3 linear) {
    const float3x3 gba = float3x3(float3(0.905, 0.10, 0.1575), float3(0.195, 0.65, 0.1425), float3(-0.10, 0.25, 0.70));
    return saturate(gba * linear * 0.91);
}

float3 sp101Profile(float3 linear) {
    const float3x3 sp101 = float3x3(float3(0.96, 0.0325, 0.001), float3(0.11, 0.89, -0.03), float3(-0.07, 0.0775, 1.029));
    return saturate(sp101 * linear * 0.935);
}

#define DISPLAY_MODE_SP101 3u
#define DISPLAY_MODE_MONOCHROME 4u
#define DISPLAY_MODE_AUTHENTIC_GBC 5u
#define DISPLAY_MODE_GBA 6u
#define DISPLAY_MODE_CRT 7u

// The frames to show, newest first, with their blending weights, and the display mode.
#define DISPLAY_FRAMES texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest, float3 weights, uint mode
#define DISPLAY_FRAMES_ARGS newest, previous, oldest, weights, mode

float4 displaySample(DISPLAY_FRAMES, sampler s, float2 position) {
    float4 color = blendedSample(newest, previous, oldest, s, position, weights);
    if (mode == DISPLAY_MODE_GBA) color.rgb = gbaProfile(color.rgb);
    return float4(color.rgb, 1.0);
}

float4 displayTexel(DISPLAY_FRAMES, sampler s, float2 texel) {
    return displaySample(DISPLAY_FRAMES_ARGS, s, (texel + 0.5) / float2(newest.get_width(), newest.get_height()));
}

float4 displayRelative(DISPLAY_FRAMES, sampler s, float2 position, float2 offset) {
    return displayTexel(DISPLAY_FRAMES_ARGS, s, floor(position * float2(newest.get_width(), newest.get_height())) + offset);
}

// The Monochrome LCD's screen, described by `MonochromeLCDParameters` in
// DisplayFilterRendering.swift; the layouts match.
struct MonochromeLCDParameters {
    float4 curveInput[5];  // each channel's tone curve knots, ascending, in linear light
    float4 curveOutput[5]; // what each knot shows
    float4 gap;            // the unlit LCD the gaps show, in linear light; its strength
    float4 cell;           // the gap's width in pixels
};

// A channel between two knots is interpolated; past the first or last, the end segment continues.
float3 monochromeTone(float3 color, constant MonochromeLCDParameters &lcd) {
    float3 t = (color - lcd.curveInput[0].rgb) / (lcd.curveInput[1].rgb - lcd.curveInput[0].rgb);
    float3 result = mix(lcd.curveOutput[0].rgb, lcd.curveOutput[1].rgb, t);
    for (uint i = 1; i < 4; ++i) {
        t = (color - lcd.curveInput[i].rgb) / (lcd.curveInput[i + 1].rgb - lcd.curveInput[i].rgb);
        result = select(result, mix(lcd.curveOutput[i].rgb, lcd.curveOutput[i + 1].rgb, t), color >= lcd.curveInput[i].rgb);
    }
    return saturate(result);
}

// How much gap lies before `position`, in pixels, with a gap `width` wide centered on every
// pixel edge.
float2 gapLength(float2 position, float width) {
    float2 shifted = position + width * 0.5;
    return floor(shifted) * width + min(fract(shifted), width);
}

// A dot-matrix screen: each pixel a square, and between the squares the unlit LCD, lighter and
// yellower than a dark pixel, as BGB's photos show it. BGB's colors are averages of defocused
// photos, gaps included, so each square is darkened by the light its gaps add and a pixel's
// average stays its shade. A gap can't add more light than the shade has, so around the darkest
// shades its strength drops to what the shade leaves room for. Each screen pixel takes the share
// of gap its footprint covers, so the gaps never alias and fade into the pixels when the screen
// is too coarse to show them.
float4 monochromeLCD(DISPLAY_FRAMES, sampler s, float2 position, constant MonochromeLCDParameters &lcd) {
    float2 texel = position * float2(newest.get_width(), newest.get_height());
    float2 footprint = max(fwidth(texel), float2(1e-5));
    float width = lcd.cell.x;
    float2 share = (gapLength(texel + footprint * 0.5, width) - gapLength(texel - footprint * 0.5, width)) / footprint;
    float covered = 1.0 - (1.0 - share.x) * (1.0 - share.y);
    // The share of each pixel its gaps take.
    float area = 2.0 * width - width * width;

    float3 shade = monochromeTone(displayTexel(DISPLAY_FRAMES_ARGS, s, floor(texel)).rgb, lcd);
    float3 room = shade / max(area * lcd.gap.rgb, float3(1e-6));
    float strength = min(lcd.gap.a, min(room.r, min(room.g, room.b)));
    float3 square = saturate((shade - strength * area * lcd.gap.rgb) / (1.0 - strength * area));
    return float4(mix(square, lcd.gap.rgb, strength * covered), 1.0);
}

// SameBoy LCD.fsh with its default constants.
float4 sameboyColorLCD(DISPLAY_FRAMES, sampler s, float2 position) {
    float2 sub_pos = fract(position * float2(newest.get_width(), newest.get_height())) * 6.0;

    float4 center = displayRelative(DISPLAY_FRAMES_ARGS, s, position, float2(0, 0));
    float4 left = displayRelative(DISPLAY_FRAMES_ARGS, s, position, float2(-1, 0));
    float4 right = displayRelative(DISPLAY_FRAMES_ARGS, s, position, float2(1, 0));

    if (sub_pos.y < 1.0) {
        float blend = 0.5 - sub_pos.y / 2.0;
        center = mix(center, displayRelative(DISPLAY_FRAMES_ARGS, s, position, float2( 0, -1)), blend);
        left =   mix(left,   displayRelative(DISPLAY_FRAMES_ARGS, s, position, float2(-1, -1)), blend);
        right =  mix(right,  displayRelative(DISPLAY_FRAMES_ARGS, s, position, float2( 1, -1)), blend);
        float edge = sub_pos.y * 0.2 + (1.0 - 0.2);
        center *= edge; left *= edge; right *= edge;
    }
    else if (sub_pos.y > 5.0) {
        float blend = (sub_pos.y - 5.0) / 2.0;
        center = mix(center, displayRelative(DISPLAY_FRAMES_ARGS, s, position, float2( 0, 1)), blend);
        left =   mix(left,   displayRelative(DISPLAY_FRAMES_ARGS, s, position, float2(-1, 1)), blend);
        right =  mix(right,  displayRelative(DISPLAY_FRAMES_ARGS, s, position, float2( 1, 1)), blend);
        float edge = (6.0 - sub_pos.y) * 0.2 + (1.0 - 0.2);
        center *= edge; left *= edge; right *= edge;
    }

    float4 midleft = mix(left, center, 0.5);
    float4 midright = mix(right, center, 0.5);

    if (sub_pos.x < 1.0) {
        return mix(float4(1.0 * center.r, 0.6 * center.g, 1.0 * left.b, 1),
                   float4(1.0 * center.r, 0.6 * center.g, 0.6 * left.b, 1), sub_pos.x);
    }
    if (sub_pos.x < 2.0) {
        return mix(float4(1.0 * center.r, 0.6 * center.g, 0.6 * left.b, 1),
                   float4(1.0 * center.r, 1.0 * center.g, 0.6 * midleft.b, 1), sub_pos.x - 1.0);
    }
    if (sub_pos.x < 3.0) {
        return mix(float4(1.0 * center.r, 1.0 * center.g, 0.6 * midleft.b, 1),
                   float4(0.6 * midright.r, 1.0 * center.g, 0.6 * center.b, 1), sub_pos.x - 2.0);
    }
    if (sub_pos.x < 4.0) {
        return mix(float4(0.6 * midright.r, 1.0 * center.g, 0.6 * center.b, 1),
                   float4(0.6 * right.r, 1.0 * center.g, 1.0 * center.b, 1), sub_pos.x - 3.0);
    }
    if (sub_pos.x < 5.0) {
        return mix(float4(0.6 * right.r, 1.0 * center.g, 1.0 * center.b, 1),
                   float4(0.6 * right.r, 0.6 * midright.g, 1.0 * center.b, 1), sub_pos.x - 4.0);
    }
    return mix(float4(0.6 * right.r, 0.6 * midright.g, 1.0 * center.b, 1),
               float4(1.0 * right.r, 0.6 * right.g, 1.0 * center.b, 1), sub_pos.x - 5.0);
}

// How much of the unit interval [a0, a1] a span [r0, r1] covers once its edges are softened by a
// box blur `blur` wide. The integral of a clamped ramp is a quadratic, so the area is exact.
float softenedEdgeIntegral(float x, float edge, float blur) {
    float u = (x - edge) / blur + 0.5;
    return blur * (u <= 0.0 ? 0.0 : (u < 1.0 ? 0.5 * u * u : u - 0.5));
}

float softenedSpanCoverage(float a0, float a1, float r0, float r1, float blur) {
    if (blur < 1.0e-6) return max(min(a1, r1) - max(a0, r0), 0.0);
    return softenedEdgeIntegral(a1, r0, blur) - softenedEdgeIntegral(a0, r0, blur)
         - softenedEdgeIntegral(a1, r1, blur) + softenedEdgeIntegral(a0, r1, blur);
}

// The area of a screen pixel `square` (x0, y0, x1, y1) that a softened rectangle covers.
float softenedRectCoverage(float4 square, float4 rect, float blur) {
    return softenedSpanCoverage(square.x, square.z, rect.x, rect.z, blur)
         * softenedSpanCoverage(square.y, square.w, rect.y, rect.w, blur);
}

// Authentic GBC 2.2 geometry with its defaults: brightness 0.6, smoothing 0.3, host subpixels off.
// Each GBC subpixel is two rectangles, which leave the notch measured from a photo of the screen.
struct AuthenticGBCGeometry {
    float4 rect1;
    float4 rect2;
    float2 scale;
    float2 origin;
    float blur;

    float coverage(float2 position) const {
        const float4 square = float4(-0.5, -0.5, 0.5, 0.5);
        return softenedRectCoverage(square, position.xyxy + rect1, blur)
             + softenedRectCoverage(square, position.xyxy + rect2, blur);
    }

    float3 pixelColor(float2 position) const {
        return float3(coverage(position + float2(origin.x - scale.x / 3.0, origin.y)),
                      coverage(position + origin),
                      coverage(position + float2(origin.x + scale.x / 3.0, origin.y)));
    }
};

float4 authenticGBC(DISPLAY_FRAMES, sampler s, float2 position) {
    float2 size = float2(newest.get_width(), newest.get_height());
    float2 scale = 1.0 / max(fwidth(position) * size, float2(1e-5));
    float2 subpixelSize = scale * mix(float2(0.296, 0.910), float2(0.75, 0.93), 0.6);
    float2 notchSize = scale * mix(float2(0.115, 0.166), float2(0.29, 0.17), 0.6);
    AuthenticGBCGeometry geometry;
    geometry.rect1 = float4(float2(0.0), subpixelSize - float2(0.0, notchSize.y));
    geometry.rect2 = float4(notchSize.x, subpixelSize.y - notchSize.y, subpixelSize);
    geometry.scale = scale;
    geometry.origin = (scale - subpixelSize) * 0.5;
    geometry.blur = 0.3 * min(scale.x, scale.y) * 0.5;
    float2 texel = position * size;
    float2 integral = floor(texel);
    float2 fraction = fract(texel);
    float2 offset = step(float2(0.5), fraction) * 2.0 - 1.0;
    float2 offsets[4] = {float2(0.0), float2(offset.x, 0.0), float2(0.0, offset.y), offset};
    float3 color = float3(0.0);
    for (uint i = 0; i < 4; ++i) {
        color += geometry.pixelColor((offsets[i] - fraction) * scale) * displayTexel(DISPLAY_FRAMES_ARGS, s, integral + offsets[i]).rgb;
    }
    return float4(color, 1.0);
}

// One television, described by `CRTParameters` in DisplayFilterRendering.swift; the layouts match.
struct CRTParameters {
    float4 geometry; // barrel curvature x, y; corner radius; vignette
    float4 beam;     // raster lines per source line; scanline hardness; horizontal hardness; brightness
    float4 mask;     // triads per source pixel (0 for none); dark; light; slot break height in source lines (0 for a grille)
    float4 glow;     // bloom amount (0 for none); bloom mip level
};

// Each source line is one or more beam passes. A beam is Gaussian across its line and its
// horizontal reconstruction is a two-tap Gaussian, as in CRT-Lottes; at its default hardness or
// harder the taps further out weigh under 1%, so they are left out.
float3 crtLine(DISPLAY_FRAMES, sampler s, float rasterLine, float x, float2 rasterSize, float linesPerSource, float hardPix) {
    float row = clamp(floor(rasterLine / linesPerSource), 0.0, rasterSize.y / linesPerSource - 1.0);
    float left = floor(x - 0.5);
    float fx = x - 0.5 - left;
    float wl = exp2(hardPix * fx * fx);
    float wr = exp2(hardPix * (1.0 - fx) * (1.0 - fx));
    float3 a = displayTexel(DISPLAY_FRAMES_ARGS, s, float2(max(left, 0.0), row)).rgb;
    float3 b = displayTexel(DISPLAY_FRAMES_ARGS, s, float2(min(left + 1.0, rasterSize.x - 1.0), row)).rgb;
    return (a * wl + b * wr) / (wl + wr);
}

// How much of each of a triad's three stripes the span [t0, t1) covers, in triads. Each stripe's
// covered length up to t is a clamped ramp per triad, so the share is exact at any footprint.
float3 stripeShares(float t0, float t1) {
    const float3 starts = float3(0.0, 1.0, 2.0) / 3.0;
    float3 upTo1 = floor(t1) / 3.0 + clamp(float3(fract(t1)) - starts, float3(0.0), float3(1.0 / 3.0));
    float3 upTo0 = floor(t0) / 3.0 + clamp(float3(fract(t0)) - starts, float3(0.0), float3(1.0 / 3.0));
    return (upTo1 - upTo0) / max(t1 - t0, 1e-5);
}

// The phosphor mask, locked to source pixels so it never beats against them. `coord` is the
// position in triads across and source lines down, and `footprint` one screen pixel's size there;
// each screen pixel takes the share of each stripe, and of a slot mask's breaks, that it covers,
// so a mask finer than the screen fades to its average instead of aliasing.
float3 crtMask(float2 coord, float2 footprint, float4 mask) {
    if (mask.x <= 0.0) return float3(1.0);
    float3 color = mix(float3(mask.y), float3(mask.z), stripeShares(coord.x - footprint.x * 0.5, coord.x + footprint.x * 0.5));
    if (mask.w > 0.0) {
        // Each stripe breaks once a source line, offset half a line on alternate triads.
        float y = coord.y + 0.5 * fmod(floor(coord.x), 2.0);
        float y0 = y - footprint.y * 0.5, y1 = y + footprint.y * 0.5;
        float broken = (floor(y1) * mask.w + min(fract(y1), mask.w)) - (floor(y0) * mask.w + min(fract(y0), mask.w));
        color *= mix(1.0, mask.y, broken / max(y1 - y0, 1e-5));
    }
    return color;
}

float4 crtDisplay(DISPLAY_FRAMES, sampler s, sampler bloomSampler, float2 position, constant CRTParameters &crt) {
    float2 size = float2(newest.get_width(), newest.get_height());
    float2 centered = position * 2.0 - 1.0;
    float2 warped = centered * (1.0 + float2(centered.y * centered.y, centered.x * centered.x) * crt.geometry.xy);
    float2 uv = warped * 0.5 + 0.5;

    // Edge and corner antialiasing and the mask's footprint come before any branch, so the
    // derivatives stay valid.
    float2 maskCoord = uv * size * float2(crt.mask.x, 1.0);
    float2 maskFootprint = fwidth(maskCoord);
    float aspect = size.x / size.y;
    // Signed distance to the rounded raster edge, in half-heights.
    float radius = crt.geometry.z;
    float2 q = abs(warped) * float2(aspect, 1.0) - (float2(aspect, 1.0) - radius);
    float edgeDistance = length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    float edge = max(fwidth(edgeDistance), 1e-5);
    float inside = 1.0 - smoothstep(-edge, edge, edgeDistance);
    if (inside <= 0.0) return float4(0, 0, 0, 1);

    float linesPerSource = crt.beam.x;
    float2 rasterSize = size * float2(1.0, linesPerSource);
    float2 raster = uv * rasterSize;
    float upper = floor(raster.y - 0.5);
    float fy = raster.y - 0.5 - upper;
    float hardScan = crt.beam.y;
    float x = uv.x * size.x;
    float3 color = crtLine(DISPLAY_FRAMES_ARGS, s, upper, x, rasterSize, linesPerSource, crt.beam.z) * exp2(hardScan * fy * fy)
                 + crtLine(DISPLAY_FRAMES_ARGS, s, upper + 1.0, x, rasterSize, linesPerSource, crt.beam.z) * exp2(hardScan * (1.0 - fy) * (1.0 - fy));
    color *= crt.beam.w;
    if (crt.glow.x > 0.0) {
        float4 glow = newest.sample(bloomSampler, uv, level(crt.glow.y)) * weights.x;
        if (weights.y > 0.0) glow += previous.sample(bloomSampler, uv, level(crt.glow.y)) * weights.y;
        if (weights.z > 0.0) glow += oldest.sample(bloomSampler, uv, level(crt.glow.y)) * weights.z;
        color += glow.rgb * crt.glow.x;
    }
    color *= crtMask(maskCoord, maskFootprint, crt.mask);
    color *= inside * (1.0 - crt.geometry.w * smoothstep(0.25, 1.7, dot(centered, centered)));
    return float4(color, 1.0);
}

float4 linearDisplay(DISPLAY_FRAMES, sampler s, sampler bloomSampler, float2 position, constant CRTParameters &crt,
                     constant MonochromeLCDParameters &monochrome) {
    float4 color;
    if (mode == DISPLAY_MODE_MONOCHROME) color = monochromeLCD(DISPLAY_FRAMES_ARGS, s, position, monochrome);
    else if (mode == DISPLAY_MODE_AUTHENTIC_GBC) color = authenticGBC(DISPLAY_FRAMES_ARGS, s, position);
    else if (mode == DISPLAY_MODE_CRT) color = crtDisplay(DISPLAY_FRAMES_ARGS, s, bloomSampler, position, crt);
    else color = sameboyColorLCD(DISPLAY_FRAMES_ARGS, s, position);
    return float4(linearToSRGB(color.rgb), 1.0);
}
