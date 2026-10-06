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

fragment float4 gameplayTextureFragment(VertexOut in [[stage_in]], texture2d<float> source [[texture(0)]],
                                       constant uint &lcdMode [[buffer(0)]]) {
    constexpr sampler nearestSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    float2 size = float2(source.get_width(), source.get_height());
    return lcdColor(source.sample(nearestSampler, in.texCoord), in.texCoord * size, lcdMode);
}

/// Fill scaling. At a scale that isn't a whole number, nearest sampling makes some Game Boy pixels
/// a screen pixel wider than others. This samples each Game Boy pixel flat and blends only across
/// its edges, over about one screen pixel, so the pixels look even and stay sharp.
fragment float4 gameplaySharpFragment(VertexOut in [[stage_in]], texture2d<float> source [[texture(0)]],
                                     constant uint &lcdMode [[buffer(0)]]) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 size = float2(source.get_width(), source.get_height());
    float2 texel = in.texCoord * size;
    float2 edge = floor(texel + 0.5);
    float2 texelsPerScreenPixel = max(fwidth(texel), float2(1e-5));
    texel = edge + clamp((texel - edge) / texelsPerScreenPixel, -0.5, 0.5);
    return lcdColor(source.sample(linearSampler, texel / size), in.texCoord * size, lcdMode);
}
