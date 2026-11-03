#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut gameplayFullscreenVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    const float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

// Frame blending: the newest frame and the two before it, weighted. The weights sum to 1, and a
// frame with no weight isn't sampled.
float4 blendedSample(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest,
                     sampler s, float2 coord, float3 weights) {
    float4 color = newest.sample(s, coord) * weights.x;
    if (weights.y > 0.0) color += previous.sample(s, coord) * weights.y;
    if (weights.z > 0.0) color += oldest.sample(s, coord) * weights.z;
    return color;
}

#include "DisplayShaders.h"

// Pixel Grid (mode 1), RGB Subpixels (mode 2) and the backlit SP's grid (mode 3). Modelled on the
// libretro LCD shaders; credited in THIRD_PARTY_NOTICES.md and Acknowledgements. Fade fine detail
// when the output has too few pixels to resolve it. The mask follows source pixels, so both
// scaling modes and both GB/GBC framebuffers keep the same LCD cell pattern. Mode 3 arrives in
// linear light and is colored by the SP101 profile first.
float4 gridColor(float4 color, float2 texel, uint mode) {
    if (mode == 0) return color;
    if (mode == DISPLAY_MODE_SP101) color = float4(linearToSRGB(sp101Profile(color.rgb)), 1.0);
    float2 footprint = max(fwidth(texel), float2(1e-5));
    float2 cell = fract(texel);
    float2 edgeDistance = min(cell, 1.0 - cell);
    float2 aperture = smoothstep(float2(0.02), float2(0.10) + footprint * 0.35, edgeDistance);
    float detail = smoothstep(1.0, 3.0, 1.0 / max(footprint.x, footprint.y));
    float grid = mix(1.0, 0.80 + 0.20 * aperture.x * aperture.y, detail);
    float3 mask = float3(grid);
    if (mode == 2) {
        // Three soft bands in each source pixel, with a little light from the other channels.
        float3 centers = float3(1.0 / 6.0, 0.5, 5.0 / 6.0);
        float3 distance = abs(float3(cell.x) - centers);
        float3 bands = 1.0 - smoothstep(float3(1.0 / 6.0) - footprint.x * 0.35,
                                      float3(1.0 / 6.0) + footprint.x * 0.35, distance);
        float subpixelDetail = smoothstep(2.0, 5.0, 1.0 / footprint.x);
        mask *= mix(float3(1.0), 0.78 + 0.22 * bands, subpixelDetail);
    }
    return float4(color.rgb * mask, color.a);
}

// Modes above 3 reconstruct a physical display from whole source pixels, so both scaling paths
// draw them the same way.
#define GAMEPLAY_FRAGMENT_ARGUMENTS VertexOut in [[stage_in]], texture2d<float> source [[texture(0)]], \
    texture2d<float> previous [[texture(1)]], texture2d<float> oldest [[texture(2)]], \
    constant uint &displayMode [[buffer(0)]], constant float4 &blendWeights [[buffer(1)]], \
    constant CRTParameters &crt [[buffer(2)]]

float4 physicalDisplay(VertexOut in, texture2d<float> source, texture2d<float> previous, texture2d<float> oldest,
                       uint displayMode, float3 weights, constant CRTParameters &crt) {
    constexpr sampler nearestSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    constexpr sampler bloomSampler(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);
    return linearDisplay(source, previous, oldest, weights, displayMode, nearestSampler, bloomSampler,
                         in.texCoord, in.position.xy, crt);
}

fragment float4 gameplayTextureFragment(GAMEPLAY_FRAGMENT_ARGUMENTS) {
    if (displayMode > DISPLAY_MODE_SP101) {
        return physicalDisplay(in, source, previous, oldest, displayMode, blendWeights.xyz, crt);
    }
    constexpr sampler nearestSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    float2 size = float2(source.get_width(), source.get_height());
    float4 color = blendedSample(source, previous, oldest, nearestSampler, in.texCoord, blendWeights.xyz);
    return gridColor(color, in.texCoord * size, displayMode);
}

/// Fill scaling. At a scale that isn't a whole number, nearest sampling makes some Game Boy pixels
/// a screen pixel wider than others. This samples each Game Boy pixel flat and blends only across
/// its edges, over about one screen pixel, so the pixels look even and stay sharp.
fragment float4 gameplaySharpFragment(GAMEPLAY_FRAGMENT_ARGUMENTS) {
    if (displayMode > DISPLAY_MODE_SP101) {
        return physicalDisplay(in, source, previous, oldest, displayMode, blendWeights.xyz, crt);
    }
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 size = float2(source.get_width(), source.get_height());
    float2 texel = in.texCoord * size;
    float2 edge = floor(texel + 0.5);
    float2 texelsPerScreenPixel = max(fwidth(texel), float2(1e-5));
    texel = edge + clamp((texel - edge) / texelsPerScreenPixel, -0.5, 0.5);
    float4 color = blendedSample(source, previous, oldest, linearSampler, texel / size, blendWeights.xyz);
    return gridColor(color, in.texCoord * size, displayMode);
}
