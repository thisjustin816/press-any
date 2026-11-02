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

// Modelled on the libretro LCD shaders; credited in THIRD_PARTY_NOTICES.md and Acknowledgements.
// Fade fine detail when the output has too few pixels to resolve it. The mask follows source
// pixels, so both scaling modes and both GB/GBC framebuffers keep the same LCD cell pattern.
float4 lcdColor(float4 color, float2 texel, uint mode) {
    if (mode == 0) return color;
    float2 footprint = max(fwidth(texel), float2(1e-5));
    float2 cell = fract(texel);
    float2 edgeDistance = min(cell, 1.0 - cell);
    float2 aperture = smoothstep(float2(0.02), float2(0.10) + footprint * 0.35, edgeDistance);
    float detail = smoothstep(1.0, 3.0, 1.0 / max(footprint.x, footprint.y));
    float grid = mix(1.0, 0.80 + 0.20 * aperture.x * aperture.y, detail);
    float3 mask = float3(grid);
    if (mode == 3) {
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

// Frame blending: the newest frame and the two before it, weighted. The weights sum to 1, and a
// frame with no weight isn't sampled.
float4 blendedSample(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest,
                     sampler s, float2 coord, float3 weights) {
    float4 color = newest.sample(s, coord) * weights.x;
    if (weights.y > 0.0) color += previous.sample(s, coord) * weights.y;
    if (weights.z > 0.0) color += oldest.sample(s, coord) * weights.z;
    return color;
}


// Television-output presets are deliberately restrained. CRT 240p models a consumer TV with
// visible beam structure and mild horizontal bleed; GameCube TV stays cleaner because Game Boy
// Player could be used through either interlaced or progressive GameCube output.
float4 tvColor(texture2d<float> newest, texture2d<float> previous, texture2d<float> older,
               sampler s, float2 coord, float2 texel, float2 size,
               float3 weights, uint mode) {
    float2 dx = float2(0.55 / max(size.x, 1.0), 0.0);
    float4 center = blendedSample(newest, previous, older, s, coord, weights);
    float4 neighbors = 0.5 * (
        blendedSample(newest, previous, older, s, coord - dx, weights) +
        blendedSample(newest, previous, older, s, coord + dx, weights)
    );
    float softness = mode == 4 ? 0.28 : 0.12;
    float4 color = mix(center, neighbors, softness);

    float cellY = fract(texel.y);
    float beam = smoothstep(0.0, 0.35, cellY) * (1.0 - smoothstep(0.65, 1.0, cellY));
    float beamAmount = mode == 4 ? 0.20 : 0.055;
    float luminance = 1.0 - beamAmount * (1.0 - beam);
    if (mode == 4) {
        luminance *= 0.975 + 0.025 * cos((texel.x + 0.5) * 6.2831853);
    }
    return float4(color.rgb * luminance, color.a);
}

fragment float4 gameplayTextureFragment(VertexOut in [[stage_in]], texture2d<float> source [[texture(0)]],
                                       texture2d<float> previous [[texture(1)]],
                                       texture2d<float> oldest [[texture(2)]],
                                       constant uint &lcdMode [[buffer(0)]],
                                       constant float4 &blendWeights [[buffer(1)]]) {
    constexpr sampler nearestSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    float2 size = float2(source.get_width(), source.get_height());
    float2 texel = in.texCoord * size;
    if (lcdMode == 4 || lcdMode == 5) {
        return tvColor(source, previous, oldest, nearestSampler, in.texCoord, texel, size, blendWeights.xyz, lcdMode);
    }
    float4 color = blendedSample(source, previous, oldest, nearestSampler, in.texCoord, blendWeights.xyz);
    return lcdColor(color, texel, lcdMode);
}

/// Fill scaling. At a scale that isn't a whole number, nearest sampling makes some Game Boy pixels
/// a screen pixel wider than others. This samples each Game Boy pixel flat and blends only across
/// its edges, over about one screen pixel, so the pixels look even and stay sharp.
fragment float4 gameplaySharpFragment(VertexOut in [[stage_in]], texture2d<float> source [[texture(0)]],
                                     texture2d<float> previous [[texture(1)]],
                                     texture2d<float> oldest [[texture(2)]],
                                     constant uint &lcdMode [[buffer(0)]],
                                     constant float4 &blendWeights [[buffer(1)]]) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 size = float2(source.get_width(), source.get_height());
    float2 texel = in.texCoord * size;
    float2 edge = floor(texel + 0.5);
    float2 texelsPerScreenPixel = max(fwidth(texel), float2(1e-5));
    texel = edge + clamp((texel - edge) / texelsPerScreenPixel, -0.5, 0.5);
    float2 sampleCoord = texel / size;
    float2 displayTexel = in.texCoord * size;
    if (lcdMode == 4 || lcdMode == 5) {
        return tvColor(source, previous, oldest, linearSampler, sampleCoord, displayTexel, size, blendWeights.xyz, lcdMode);
    }
    float4 color = blendedSample(source, previous, oldest, linearSampler, sampleCoord, blendWeights.xyz);
    return lcdColor(color, displayTexel, lcdMode);
}
