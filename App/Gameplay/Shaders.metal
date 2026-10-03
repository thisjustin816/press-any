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

fragment float4 gameplayTextureFragment(VertexOut in [[stage_in]], texture2d<float> source [[texture(0)]]) {
    constexpr sampler nearestSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    return source.sample(nearestSampler, in.texCoord);
}

/// Fill scaling. At a scale that isn't a whole number, nearest sampling makes some Game Boy pixels
/// a screen pixel wider than others. This samples each Game Boy pixel flat and blends only across
/// its edges, over about one screen pixel, so the pixels look even and stay sharp.
fragment float4 gameplaySharpFragment(VertexOut in [[stage_in]], texture2d<float> source [[texture(0)]]) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 size = float2(source.get_width(), source.get_height());
    float2 texel = in.texCoord * size;
    float2 edge = floor(texel + 0.5);
    float2 texelsPerScreenPixel = max(fwidth(texel), float2(1e-5));
    texel = edge + clamp((texel - edge) / texelsPerScreenPixel, -0.5, 0.5);
    return source.sample(linearSampler, texel / size);
}
