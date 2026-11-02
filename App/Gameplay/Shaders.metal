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

// Barrel distortion makes the raster bow toward the glass edges. Values are intentionally much
// gentler than novelty/fisheye CRT effects while remaining visible on a phone-sized display.
float2 crtWarp(float2 coord, float curvature) {
    float2 centered = coord * 2.0 - 1.0;
    float radius2 = dot(centered, centered);
    centered *= 1.0 + curvature * radius2;
    return centered * 0.5 + 0.5;
}

// RGB aperture-grille style phosphor mask. It is anchored to output pixels rather than source
// pixels so it stays fine-grained as the Game Boy image is scaled.
float3 crtPhosphorMask(float2 pixel, float strength) {
    float phase = fmod(floor(pixel.x), 3.0);
    float3 phosphor = phase < 1.0 ? float3(1.00, 0.70, 0.70)
                    : phase < 2.0 ? float3(0.70, 1.00, 0.70)
                                  : float3(0.70, 0.70, 1.00);
    return mix(float3(1.0), phosphor, strength);
}

// A fuller CRT treatment in the spirit of the better real-time CRT shaders: curved glass,
// scanline/beam structure, phosphor mask, analog softness, bloom and edge falloff. Mode 4 is the
// stronger 240p treatment used by Super Game Boy. Mode 5 keeps the same CRT characteristics but
// doubles the raster density and softens them for Game Boy Player's 480i-style television output.
float4 crtColor(texture2d<float> newest, texture2d<float> previous, texture2d<float> older,
                sampler s, float2 coord, float2 size, float2 outputPixel,
                float3 weights, uint mode) {
    bool is240p = mode == 4;
    // Game Boy Player targets a later flat-face CRT look: visibly CRT, but much flatter than SGB.
    float curvature = is240p ? 0.075 : 0.028;
    float2 warped = crtWarp(coord, curvature);
    if (any(warped < float2(0.0)) || any(warped > float2(1.0))) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 texelSize = 1.0 / max(size, float2(1.0));
    float2 horizontal = float2(texelSize.x, 0.0);
    float2 vertical = float2(0.0, texelSize.y);
    float4 center = blendedSample(newest, previous, older, s, warped, weights);
    float4 axial = 0.25 * (
        blendedSample(newest, previous, older, s, warped - horizontal, weights) +
        blendedSample(newest, previous, older, s, warped + horizontal, weights) +
        blendedSample(newest, previous, older, s, warped - vertical, weights) +
        blendedSample(newest, previous, older, s, warped + vertical, weights)
    );
    float softness = is240p ? 0.24 : 0.18;
    float3 color = mix(center.rgb, axial.rgb, softness);

    // Bright areas spill into their neighbors instead of ending at a perfectly hard digital edge.
    float3 bloomSource = max(axial.rgb - float3(0.45), float3(0.0));
    color += bloomSource * (is240p ? 0.20 : 0.16);

    // 240p has one beam per source row. The Game Boy Player treatment uses a denser two-beam
    // structure to suggest the line-doubled/interlaced GameCube television presentation.
    float rasterScale = is240p ? 1.0 : 2.0;
    float rasterY = warped.y * size.y * rasterScale;
    float beam = sin(fract(rasterY) * 3.14159265);
    beam = pow(max(beam, 0.0), is240p ? 0.72 : 0.82);
    float beamFloor = is240p ? 0.52 : 0.64;
    color *= mix(beamFloor, 1.0, beam);

    // Fine RGB phosphors remain visible between scanlines, as on a close CRT photograph.
    color *= crtPhosphorMask(outputPixel, is240p ? 0.34 : 0.26);

    // Curved glass falls off toward the corners and picks up a subtle bright halo in the middle.
    float2 centered = warped * 2.0 - 1.0;
    float radius2 = dot(centered, centered);
    float vignette = 1.0 - (is240p ? 0.24 : 0.18) * smoothstep(0.30, 1.65, radius2);
    float glassGlow = 1.0 + (is240p ? 0.035 : 0.025) * (1.0 - smoothstep(0.0, 1.15, radius2));
    color *= vignette * glassGlow;

    // Feather the active raster into black near the curved glass boundary instead of clipping it
    // at a perfectly rectangular digital edge.
    float2 edge = min(warped, 1.0 - warped);
    float border = smoothstep(0.0, is240p ? 0.018 : 0.014, min(edge.x, edge.y));
    color *= border;

    return float4(saturate(color), center.a);
}

fragment float4 gameplayTextureFragment(VertexOut in [[stage_in]], texture2d<float> source [[texture(0)]],
                                       texture2d<float> previous [[texture(1)]],
                                       texture2d<float> oldest [[texture(2)]],
                                       constant uint &lcdMode [[buffer(0)]],
                                       constant float4 &blendWeights [[buffer(1)]]) {
    constexpr sampler nearestSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    float2 size = float2(source.get_width(), source.get_height());
    if (lcdMode == 4 || lcdMode == 5) {
        return crtColor(source, previous, oldest, nearestSampler, in.texCoord, size,
                        in.position.xy, blendWeights.xyz, lcdMode);
    }
    float2 texel = in.texCoord * size;
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
    if (lcdMode == 4 || lcdMode == 5) {
        return crtColor(source, previous, oldest, linearSampler, sampleCoord, size,
                        in.position.xy, blendWeights.xyz, lcdMode);
    }
    float2 displayTexel = in.texCoord * size;
    float4 color = blendedSample(source, previous, oldest, linearSampler, sampleCoord, blendWeights.xyz);
    return lcdColor(color, displayTexel, lcdMode);
}
