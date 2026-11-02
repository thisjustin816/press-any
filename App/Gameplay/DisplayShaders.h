// SameBoy LCD filters: Lior Halphon, Expat. Authentic GBC: fishku, CC0.
// CRT-Lottes: Timothy Lottes, public domain. GBA/SP101 colors: Pokefan531 and hunterk, public domain.
// Pinned sources, adaptation details and bundled notices are listed in THIRD_PARTY_NOTICES.md.
#pragma once

float3 displayLinear(float3 color) { return pow(max(color, 0.0), float3(2.2)); }
float3 displayEncoded(float3 color) { return pow(max(color, 0.0), float3(1.0 / 2.2)); }

float3 handheldColor(float3 color, uint mode) {
    if (mode != 7 && mode != 8) return color;
    float3 linear = displayLinear(color);
    // Upstream sRGB profiles and default luminance; these are column-major matrices.
    float3x3 matrix = mode == 8
        ? float3x3(float3(0.96, 0.0325, 0.001), float3(0.11, 0.89, -0.03), float3(-0.07, 0.0775, 1.029))
        : float3x3(float3(0.905, 0.10, 0.1575), float3(0.195, 0.65, 0.1425), float3(-0.10, 0.25, 0.70));
    return displayEncoded(clamp(matrix * linear * (mode == 8 ? 0.935 : 0.91), 0.0, 1.0));
}

float4 displaySample(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest, sampler sampleSampler, float3 weights, float2 position, uint mode) {
    float4 color = blendedSample(newest, previous, oldest, sampleSampler, position, weights);
    return float4(displayLinear(handheldColor(color.rgb, mode)), 1.0);
}

float4 displayRelative(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest, sampler sampleSampler, float3 weights, float2 position, float2 offset, uint mode) {
    float2 size = float2(newest.get_width(), newest.get_height());
    return displaySample(newest, previous, oldest, sampleSampler, weights, (floor(position * size) + 0.5 + offset) / size, mode);
}

float4 sameboyMonoLCD(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest, sampler sampleSampler, float3 weights, float2 position, float2 input_resolution, uint mode) {

    float2 pixel = position * input_resolution - float2(0.5, 0.5);

    float4 q11 = displaySample(newest, previous, oldest, sampleSampler, weights, (floor(pixel) + 0.5) / input_resolution, mode);
    float4 q12 = displaySample(newest, previous, oldest, sampleSampler, weights, (float2(floor(pixel.x), ceil(pixel.y)) + 0.5) / input_resolution, mode);
    float4 q21 = displaySample(newest, previous, oldest, sampleSampler, weights, (float2(ceil(pixel.x), floor(pixel.y)) + 0.5) / input_resolution, mode);
    float4 q22 = displaySample(newest, previous, oldest, sampleSampler, weights, (ceil(pixel) + 0.5) / input_resolution, mode);

    float2 s = smoothstep(0., 1., fract(pixel));

    float4 r1 = mix(q11, q21, s.x);
    float4 r2 = mix(q12, q22, s.x);

    float2 pos = fract(position * input_resolution);
    float2 sub_pos = pos * 6.0;

    float multiplier = 1.0;

    if (sub_pos.y < 1.0) {
        multiplier *= sub_pos.y * 0.25 + (1.0 - 0.25);
    }
    else if (sub_pos.y > 5.0) {
        multiplier *= (6.0 - sub_pos.y) * 0.25 + (1.0 - 0.25);
    }

    if (sub_pos.x < 1.0) {
        multiplier *= sub_pos.x * 0.25 + (1.0 - 0.25);
    }
    else if (sub_pos.x > 5.0) {
        multiplier *= (6.0 - sub_pos.x) * 0.25 + (1.0 - 0.25);
    }

    float4 pre_shadow = mix(displaySample(newest, previous, oldest, sampleSampler, weights, position, mode) * multiplier, mix(r1, r2, s.y), 0.4);
    pre_shadow.a = 1.0;
    pixel += float2(-0.6, -0.8);

    q11 = displaySample(newest, previous, oldest, sampleSampler, weights, (floor(pixel) + 0.5) / input_resolution, mode);
    q12 = displaySample(newest, previous, oldest, sampleSampler, weights, (float2(floor(pixel.x), ceil(pixel.y)) + 0.5) / input_resolution, mode);
    q21 = displaySample(newest, previous, oldest, sampleSampler, weights, (float2(ceil(pixel.x), floor(pixel.y)) + 0.5) / input_resolution, mode);
    q22 = displaySample(newest, previous, oldest, sampleSampler, weights, (ceil(pixel) + 0.5) / input_resolution, mode);

    r1 = mix(q11, q21, fract(pixel.x));
    r2 = mix(q12, q22, fract(pixel.x));

    float4 shadow = mix(r1, r2, fract(pixel.y));
    return mix(min(shadow, pre_shadow), pre_shadow, 0.75);

}

float4 sameboyColorLCD(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest, sampler sampleSampler, float3 weights, float2 position, float2 input_resolution, uint mode) {

    float2 pos = fract(position * input_resolution);
    float2 sub_pos = pos * 6.0;

    float4 center = displayRelative(newest, previous, oldest, sampleSampler, weights, position, float2(0, 0), mode);
    float4 left = displayRelative(newest, previous, oldest, sampleSampler, weights, position, float2(-1, 0), mode);
    float4 right = displayRelative(newest, previous, oldest, sampleSampler, weights, position, float2(1, 0), mode);

    if (sub_pos.y < 1.0) {
        center = mix(center, displayRelative(newest, previous, oldest, sampleSampler, weights, position, float2( 0, -1), mode), 0.5 - sub_pos.y / 2.0);
        left =   mix(left,   displayRelative(newest, previous, oldest, sampleSampler, weights, position, float2(-1, -1), mode), 0.5 - sub_pos.y / 2.0);
        right =  mix(right,  displayRelative(newest, previous, oldest, sampleSampler, weights, position, float2( 1, -1), mode), 0.5 - sub_pos.y / 2.0);
        center *= sub_pos.y * 0.2 + (1.0 - 0.2);
        left *= sub_pos.y * 0.2 + (1.0 - 0.2);
        right *= sub_pos.y * 0.2 + (1.0 - 0.2);
    }
    else if (sub_pos.y > 5.0) {
        center = mix(center, displayRelative(newest, previous, oldest, sampleSampler, weights, position, float2( 0, 1), mode), (sub_pos.y - 5.0) / 2.0);
        left =   mix(left,   displayRelative(newest, previous, oldest, sampleSampler, weights, position, float2(-1, 1), mode), (sub_pos.y - 5.0) / 2.0);
        right =  mix(right,  displayRelative(newest, previous, oldest, sampleSampler, weights, position, float2( 1, 1), mode), (sub_pos.y - 5.0) / 2.0);
        center *= (6.0 - sub_pos.y) * 0.2 + (1.0 - 0.2);
        left *= (6.0 - sub_pos.y) * 0.2 + (1.0 - 0.2);
        right *= (6.0 - sub_pos.y) * 0.2 + (1.0 - 0.2);
    }


    float4 midleft = mix(left, center, 0.5);
    float4 midright = mix(right, center, 0.5);

    float4 ret;
    if (sub_pos.x < 1.0) {
        ret = mix(float4(1.0 * center.r, 0.6 * center.g, 1.0 * left.b, 1),
                  float4(1.0 * center.r, 0.6 * center.g, 0.6  * left.b, 1),
                  sub_pos.x);
    }
    else if (sub_pos.x < 2.0) {
        ret = mix(float4(1.0 * center.r, 0.6  * center.g, 0.6 * left.b, 1),
                  float4(1.0 * center.r, 1.0 * center.g, 0.6 * midleft.b, 1),
                  sub_pos.x - 1.0);
    }
    else if (sub_pos.x < 3.0) {
        ret = mix(float4(1.0 * center.r  , 1.0 * center.g, 0.6 * midleft.b, 1),
                  float4(0.6  * midright.r, 1.0 * center.g, 0.6 * center.b, 1),
                  sub_pos.x - 2.0);
    }
    else if (sub_pos.x < 4.0) {
        ret = mix(float4(0.6 * midright.r, 1.0 * center.g , 0.6  * center.b, 1),
                  float4(0.6 * right.r   , 1.0  * center.g, 1.0 * center.b, 1),
                  sub_pos.x - 3.0);
    }
    else if (sub_pos.x < 5.0) {
        ret = mix(float4(0.6 * right.r, 1.0 * center.g  , 1.0 * center.b, 1),
                  float4(0.6 * right.r, 0.6  * midright.g, 1.0 * center.b, 1),
                  sub_pos.x - 4.0);
    }
    else {
        ret = mix(float4(0.6  * right.r, 0.6 * midright.g, 1.0 * center.b, 1),
                  float4(1.0 * right.r, 0.6 * right.g  ,  1.0 * center.b, 1),
                  sub_pos.x - 5.0);
    }

    return ret;

}

// Computes intersection area between pixels and geometric shapes for perfect (analytical)
// anti-aliasing.
// If the pixel square that is passed in has unit area, the result can be directly converted to a
// color.

float intersect_rect_area(float4 px_square, float4 rect) {
    const float2 bl = max(px_square.xy, rect.xy);
    const float2 tr = min(px_square.zw, rect.zw);
    const float2 coverage = max(tr - bl, float2(0.0));
    return coverage.x * coverage.y;
}

float intersect_blurred_rect_area(float4 px_square, float4 rect, float blur) {
    float4 range = float4(rect.zw - rect.xy, rect.zw - rect.xy);
    float4 linear = clamp(px_square - rect.xyxy, float4(0.0), range);

    // Early out: If blur is very small, return perfectly sharp rectangle intersection area.
    if (blur < 1.0e-6) {
        return (linear.z - linear.x) * (linear.w - linear.y);
    }

    float4 center = float4(0.5 * (rect.xy + rect.zw), 0.5 * (rect.xy + rect.zw));
    float4 dist_to_center = abs(px_square - center);
    float4 blur_vec = float4(blur);

    float4 x_n = max(0.5 * (max(range, blur_vec) + blur_vec) - dist_to_center, float4(0.0)) / blur_vec;
    // Quartic polynomial fit to function:
    // x / 2 + exp(-x ^ 2 / 2) / sqrt(2 * pi) + x / 2 * erf(x / sqrt(2));
    // Subject to y(0) = 0, y'(0) = 0, y(1) = 1/2, y'(1) = 1
    const float3 c = float3(-0.3635, 0.727, 0.1365);
    float4 poly = fma(fma(c.xxxx, x_n, c.yyyy), x_n, c.zzzz) * x_n * x_n * min(range, blur_vec);
    // Exploit point symmetry around center
    float4 transition = mix(poly, range - poly, step(center, px_square));

    // Determine if we are in the linear or transitional part.
    float4 res = mix(linear, transition, step(0.5 * (range - blur_vec), dist_to_center));
    return (res.z - res.x) * (res.w - res.y);
}


// Authentic GBC 2.2, fishku (CC0): single-pass preset with upstream defaults.
struct AuthenticGBCGeometry {
    float4 rect1;
    float4 rect2;
    float2 scale;
    float2 origin;
    float blur;

    float coverage(float4 square, float2 position) const {
        return intersect_blurred_rect_area(square, position.xyxy + rect1, blur)
             + intersect_blurred_rect_area(square, position.xyxy + rect2, blur);
    }

    float3 pixelColor(float2 position) const {
        float4 square = float4(-0.5, -0.5, 0.5, 0.5);
        return float3(coverage(square, position + float2(origin.x - scale.x / 3.0, origin.y)),
                      coverage(square, position + origin),
                      coverage(square, position + float2(origin.x + scale.x / 3.0, origin.y)));
    }
};

float4 authenticGBC(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest, sampler sampleSampler, float3 weights, float2 position, float2 size) {
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
        float3 sample = displaySample(newest, previous, oldest, sampleSampler, weights, (integral + offsets[i] + 0.5) / size, 6).rgb;
        color += geometry.pixelColor((offsets[i] - fraction) * scale) * sample;
    }
    return float4(displayEncoded(color), 1.0);
}


// CRT-Lottes default sRGB transfer, Gaussian kernels, mask 3 and bloom amount 0.15.
float lottesLinear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}
float lottesEncoded(float c) {
    return c < 0.0031308 ? c * 12.92 : 1.055 * pow(c, 0.41666) - 0.055;
}
float3 lottesFetch(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest, sampler sampleSampler, float3 weights, float2 rasterSize, uint mode, uint fieldParity, float2 pos,float2 off){
  pos=(floor(pos*rasterSize+off)+float2(0.5,0.5))/rasterSize;
  if (any(pos < float2(0.0)) || any(pos > float2(1.0))) return float3(0.0);
  bool retainedField = mode == 5 && uint(floor(pos.y * rasterSize.y)) % 2 != (fieldParity & 1);
  float3 color = retainedField
      ? blendedSample(previous, oldest, oldest, sampleSampler, pos, weights).rgb
      : blendedSample(newest, previous, oldest, sampleSampler, pos, weights).rgb;
  return float3(lottesLinear(color.r), lottesLinear(color.g), lottesLinear(color.b));
}

// Distance in emulated pixels to nearest texel.
float2 lottesDist(float2 rasterSize, float2 pos)
{
    pos = pos*rasterSize;

    return -((pos - floor(pos)) - float2(0.5));
}

// 1D Gaussian.
float lottesGaus(float pos, float scale)
{
    return exp2(scale*pow(abs(pos), 2.0));
}

// 3-tap Gaussian filter along horz line.
float3 lottesHorz3(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest, sampler sampleSampler, float3 weights, float2 rasterSize, uint mode, uint fieldParity, float2 pos, float off)
{
    float3 b    = lottesFetch(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos, float2(-1.0, off));
    float3 c    = lottesFetch(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos, float2( 0.0, off));
    float3 d    = lottesFetch(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos, float2( 1.0, off));
    float dst = lottesDist(rasterSize, pos).x;

    // Convert distance to weight.
    float scale = -3.0;
    float wb = lottesGaus(dst-1.0,scale);
    float wc = lottesGaus(dst+0.0,scale);
    float wd = lottesGaus(dst+1.0,scale);

    // Return filtered sample.
    return (b*wb+c*wc+d*wd)/(wb+wc+wd);
}

// 5-tap Gaussian filter along horz line.
float3 lottesHorz5(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest, sampler sampleSampler, float3 weights, float2 rasterSize, uint mode, uint fieldParity, float2 pos,float off){
    float3 a = lottesFetch(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos,float2(-2.0, off));
    float3 b = lottesFetch(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos,float2(-1.0, off));
    float3 c = lottesFetch(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos,float2( 0.0, off));
    float3 d = lottesFetch(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos,float2( 1.0, off));
    float3 e = lottesFetch(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos,float2( 2.0, off));

    float dst = lottesDist(rasterSize, pos).x;
    // Convert distance to weight.
    float scale = -3.0;
    float wa = lottesGaus(dst - 2.0, scale);
    float wb = lottesGaus(dst - 1.0, scale);
    float wc = lottesGaus(dst + 0.0, scale);
    float wd = lottesGaus(dst + 1.0, scale);
    float we = lottesGaus(dst + 2.0, scale);

    // Return filtered sample.
    return (a*wa+b*wb+c*wc+d*wd+e*we)/(wa+wb+wc+wd+we);
}

// 7-tap Gaussian filter along horz line.
float3 lottesHorz7(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest, sampler sampleSampler, float3 weights, float2 rasterSize, uint mode, uint fieldParity, float2 pos,float off)
{
    float3 a = lottesFetch(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos, float2(-3.0, off));
    float3 b = lottesFetch(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos, float2(-2.0, off));
    float3 c = lottesFetch(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos, float2(-1.0, off));
    float3 d = lottesFetch(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos, float2( 0.0, off));
    float3 e = lottesFetch(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos, float2( 1.0, off));
    float3 f = lottesFetch(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos, float2( 2.0, off));
    float3 g = lottesFetch(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos, float2( 3.0, off));

    float dst = lottesDist(rasterSize, pos).x;
    // Convert distance to weight.
    float scale = -1.5;
    float wa = lottesGaus(dst - 3.0, scale);
    float wb = lottesGaus(dst - 2.0, scale);
    float wc = lottesGaus(dst - 1.0, scale);
    float wd = lottesGaus(dst + 0.0, scale);
    float we = lottesGaus(dst + 1.0, scale);
    float wf = lottesGaus(dst + 2.0, scale);
    float wg = lottesGaus(dst + 3.0, scale);

    // Return filtered sample.
    return (a*wa+b*wb+c*wc+d*wd+e*we+f*wf+g*wg)/(wa+wb+wc+wd+we+wf+wg);
}

// Return scanline weight.
float lottesScan(float2 rasterSize, float2 pos, float off)
{
    float dst = lottesDist(rasterSize, pos).y;

    return lottesGaus(dst + off, -8.0);
}

// Return scanline weight for bloom.
float lottesBloomScan(float2 rasterSize, float2 pos, float off)
{
    float dst = lottesDist(rasterSize, pos).y;

    return lottesGaus(dst + off, -2.0);
}

// Allow nearest three lines to effect pixel.
float3 lottesTri(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest, sampler sampleSampler, float3 weights, float2 rasterSize, uint mode, uint fieldParity, float2 pos)
{
    float3 a = lottesHorz3(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos,-1.0);
    float3 b = lottesHorz5(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos, 0.0);
    float3 c = lottesHorz3(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos, 1.0);

    float wa = lottesScan(rasterSize, pos,-1.0);
    float wb = lottesScan(rasterSize, pos, 0.0);
    float wc = lottesScan(rasterSize, pos, 1.0);

    return a*wa + b*wb + c*wc;
}

// Small bloom.
float3 lottesBloom(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest, sampler sampleSampler, float3 weights, float2 rasterSize, uint mode, uint fieldParity, float2 pos)
{
    float3 a = lottesHorz5(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos,-2.0);
    float3 b = lottesHorz7(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos,-1.0);
    float3 c = lottesHorz7(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos, 0.0);
    float3 d = lottesHorz7(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos, 1.0);
    float3 e = lottesHorz5(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, pos, 2.0);

    float wa = lottesBloomScan(rasterSize, pos,-2.0);
    float wb = lottesBloomScan(rasterSize, pos,-1.0);
    float wc = lottesBloomScan(rasterSize, pos, 0.0);
    float wd = lottesBloomScan(rasterSize, pos, 1.0);
    float we = lottesBloomScan(rasterSize, pos, 2.0);

    return a*wa+b*wb+c*wc+d*wd+e*we;
}

// Distortion of scanlines, and end of screen alpha.
float2 lottesWarp(float2 pos)
{
    pos  = pos*2.0-1.0;
    pos *= float2(1.0 + (pos.y*pos.y)*0.031, 1.0 + (pos.x*pos.x)*0.041);

    return pos*0.5 + 0.5;
}

// Shadow mask.
float3 lottesMask(float2 pos) {
    float3 mask = float3(0.5);
    pos.x = fract((pos.x + pos.y * 3.0) / 6.0);
    if (pos.x < 0.333) mask.r = 1.5;
    else if (pos.x < 0.666) mask.g = 1.5;
    else mask.b = 1.5;
    return mask;
}


float4 lottesCRT(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest, sampler sampleSampler, float3 weights, float2 position, float2 size, float2 outputPixel,
                 uint mode, uint fieldParity) {
    float2 warped = lottesWarp(position);
    // Antialias the raster edge before any divergent branch.
    float2 footprint = max(fwidth(warped), float2(1e-5));
    float2 edge = min(warped, 1.0 - warped);
    float feather = smoothstep(0.0, footprint.x, edge.x) * smoothstep(0.0, footprint.y, edge.y);
    if (any(warped < float2(0.0)) || any(warped > float2(1.0))) return float4(0, 0, 0, 1);
    // Weave the current and preceding fields into the denser GBP raster. Each field uses
    // the source image from its own presentation; this adapter does not change core timing.
    float2 rasterSize = size * float2(1.0, mode == 5 ? 2.0 : 1.0);
    float2 fieldPosition = warped;
    float3 color = lottesTri(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, fieldPosition);
    color += lottesBloom(newest, previous, oldest, sampleSampler, weights, rasterSize, mode, fieldParity, fieldPosition) * 0.15;
    color *= lottesMask(outputPixel);
    float2 center = warped * 2.0 - 1.0;
    color *= feather * (1.0 - 0.18 * smoothstep(0.30, 1.65, dot(center, center)));
    color = max(color, float3(0.0));
    return float4(saturate(float3(lottesEncoded(color.r), lottesEncoded(color.g), lottesEncoded(color.b))), 1.0);
}

float4 filteredDisplay(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest, sampler sampleSampler, float3 weights, float2 position, float2 outputPixel,
                       uint mode, uint fieldParity) {
    float2 size = float2(newest.get_width(), newest.get_height());
    if (mode == 4 || mode == 5) return lottesCRT(newest, previous, oldest, sampleSampler, weights, position, size, outputPixel, mode, fieldParity);
    if (mode == 6) return authenticGBC(newest, previous, oldest, sampleSampler, weights, position, size);
    float4 linear = mode == 1
        ? sameboyMonoLCD(newest, previous, oldest, sampleSampler, weights, position, size, mode)
        : sameboyColorLCD(newest, previous, oldest, sampleSampler, weights, position, size, mode);
    return float4(displayEncoded(linear.rgb), 1.0);
}
