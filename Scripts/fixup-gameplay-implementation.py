from pathlib import Path

path = Path("Scripts/implement-gameplay-presets.py")
text = path.read_text()

# These replacements align the temporary implementation script with the current repository source.
# Keep the source-critical shader/UI anchors strict; cosmetic picker-copy cleanup below is best effort.
replacements = {
    '''anchor = ''' + "'''" + '''float4 blendedSample(texture2d<float> newest, texture2d<float> previous, texture2d<float> older,
                     sampler s, float2 coord, constant float4 &weights) {
    float4 color = newest.sample(s, coord) * weights.x;
    if (weights.y > 0) color += previous.sample(s, coord) * weights.y;
    if (weights.z > 0) color += older.sample(s, coord) * weights.z;
    return color;
}
''' + "'''": '''anchor = ''' + "'''" + '''float4 blendedSample(texture2d<float> newest, texture2d<float> previous, texture2d<float> oldest,
                     sampler s, float2 coord, float3 weights) {
    float4 color = newest.sample(s, coord) * weights.x;
    if (weights.y > 0.0) color += previous.sample(s, coord) * weights.y;
    if (weights.z > 0.0) color += oldest.sample(s, coord) * weights.z;
    return color;
}
''' + "'''",
    '''               constant float4 &weights, uint mode) {''': '''               float3 weights, uint mode) {''',
    '''old_nearest = ''' + "'''" + '''    float4 color = blendedSample(newest, previous, older, s, in.texCoord, blendWeights);
    return lcdColor(color, in.texCoord * size, lcdMode);''' + "'''": '''old_nearest = ''' + "'''" + '''    float4 color = blendedSample(source, previous, oldest, nearestSampler, in.texCoord, blendWeights.xyz);
    return lcdColor(color, in.texCoord * size, lcdMode);''' + "'''",
    '''new_nearest = ''' + "'''" + '''    float2 texel = in.texCoord * size;
    if (lcdMode == 4 || lcdMode == 5) {
        return tvColor(newest, previous, older, s, in.texCoord, texel, size, blendWeights, lcdMode);
    }
    float4 color = blendedSample(newest, previous, older, s, in.texCoord, blendWeights);
    return lcdColor(color, texel, lcdMode);''' + "'''": '''new_nearest = ''' + "'''" + '''    float2 texel = in.texCoord * size;
    if (lcdMode == 4 || lcdMode == 5) {
        return tvColor(source, previous, oldest, nearestSampler, in.texCoord, texel, size, blendWeights.xyz, lcdMode);
    }
    float4 color = blendedSample(source, previous, oldest, nearestSampler, in.texCoord, blendWeights.xyz);
    return lcdColor(color, texel, lcdMode);''' + "'''",
    '''old_sharp = ''' + "'''" + '''    float4 color = blendedSample(newest, previous, older, s, texel / size, blendWeights);
    return lcdColor(color, in.texCoord * size, lcdMode);''' + "'''": '''old_sharp = ''' + "'''" + '''    float4 color = blendedSample(source, previous, oldest, linearSampler, texel / size, blendWeights.xyz);
    return lcdColor(color, in.texCoord * size, lcdMode);''' + "'''",
    '''new_sharp = ''' + "'''" + '''    float2 sampleCoord = texel / size;
    float2 displayTexel = in.texCoord * size;
    if (lcdMode == 4 || lcdMode == 5) {
        return tvColor(newest, previous, older, s, sampleCoord, displayTexel, size, blendWeights, lcdMode);
    }
    float4 color = blendedSample(newest, previous, older, s, sampleCoord, blendWeights);
    return lcdColor(color, displayTexel, lcdMode);''' + "'''": '''new_sharp = ''' + "'''" + '''    float2 sampleCoord = texel / size;
    float2 displayTexel = in.texCoord * size;
    if (lcdMode == 4 || lcdMode == 5) {
        return tvColor(source, previous, oldest, linearSampler, sampleCoord, displayTexel, size, blendWeights.xyz, lcdMode);
    }
    float4 color = blendedSample(source, previous, oldest, linearSampler, sampleCoord, blendWeights.xyz);
    return lcdColor(color, displayTexel, lcdMode);''' + "'''",
    '''import EmulatorDomain\nimport SwiftUI\n\nstruct GameplayPresetRow''': '''import EmulatorDomain\nimport Foundation\nimport SwiftUI\n\nstruct GameplayPresetRow''',
}

for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f"fixup anchor missing: {old[:100]!r}")
    text = text.replace(old, new, 1)

# Optional copy/picker cleanups are allowed to miss if the main script already has the right text.
text = text.replace(
    'source = source.replace(r"ForEach(DisplayFilter.allCases, id: \\\\.self)", r"ForEach(DisplayFilter.handheldCases, id: \\\\.self)")',
    'source = source.replace(r"ForEach(DisplayFilter.allCases, id: \\.self)", r"ForEach(DisplayFilter.handheldCases, id: \\.self)")',
)
text = text.replace(
    'source = source.replace("LCD filters come with \\\\\\(PlusProduct.name).", "Display filters come with \\\\\\(PlusProduct.name).")',
    'source = source.replace("LCD filters come with \\\\(PlusProduct.name).", "Display filters come with \\\\(PlusProduct.name).")',
)

path.write_text(text)
