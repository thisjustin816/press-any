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

fragment float4 gameplayTextureFragment(VertexOut in [[stage_in]], texture2d<float> source [[texture(0)]],
                                       texture2d<float> previous [[texture(1)]],
                                       texture2d<float> oldest [[texture(2)]],
                                       constant uint &displayMode [[buffer(0)]],
                                       constant float4 &blendWeights [[buffer(1)]],
                                       constant uint &fieldParity [[buffer(2)]]) {
    constexpr sampler nearestSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    if (displayMode == 0) return blendedSample(source, previous, oldest, nearestSampler, in.texCoord, blendWeights.xyz);
    return filteredDisplay(source, previous, oldest, nearestSampler, blendWeights.xyz,
                           in.texCoord, in.position.xy, displayMode, fieldParity);
}

fragment float4 gameplaySharpFragment(VertexOut in [[stage_in]], texture2d<float> source [[texture(0)]],
                                     texture2d<float> previous [[texture(1)]],
                                     texture2d<float> oldest [[texture(2)]],
                                     constant uint &displayMode [[buffer(0)]],
                                     constant float4 &blendWeights [[buffer(1)]],
                                     constant uint &fieldParity [[buffer(2)]]) {
    constexpr sampler nearestSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    // Display simulation owns reconstruction and needs continuous coordinates for its raster.
    if (displayMode != 0) {
        return filteredDisplay(source, previous, oldest, nearestSampler, blendWeights.xyz,
                               in.texCoord, in.position.xy, displayMode, fieldParity);
    }
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 size = float2(source.get_width(), source.get_height());
    float2 texel = in.texCoord * size;
    float2 edge = floor(texel + 0.5);
    float2 footprint = max(fwidth(texel), float2(1e-5));
    texel = edge + clamp((texel - edge) / footprint, -0.5, 0.5);
    return blendedSample(source, previous, oldest, linearSampler, texel / size, blendWeights.xyz);
}
