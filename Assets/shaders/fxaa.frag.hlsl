// FXAA Fragment Shader
// Fast Approximate Anti-Aliasing (quality variant).
// Operates on LDR color after tone mapping - needs perceptual luminance.
// See CONVENTIONS.md for shader rules.

cbuffer FXAAParams : register(b0)
{
    float2 TexelSize;          // 1.0 / screenSize
    float SubpixelQuality;    // 0.0 = off, 0.75 = default, 1.0 = max
    float EdgeThreshold;      // 0.166 = default (lower = more edges)
    float EdgeThresholdMin;   // 0.0312 = default (skip very dark areas)
    float3 _Pad;
};

Texture2D SceneColor : register(t0);
SamplerState LinearSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

float Luminance(float3 color)
{
    return dot(color, float3(0.299, 0.587, 0.114));
}

float4 main(FragmentInput input) : SV_Target
{
    float2 uv = input.TexCoord;

    // Sample center and 4 cardinal neighbors
    float3 colorCenter = SceneColor.Sample(LinearSampler, uv).rgb;
    float3 colorN = SceneColor.Sample(LinearSampler, uv + float2(0, -TexelSize.y)).rgb;
    float3 colorS = SceneColor.Sample(LinearSampler, uv + float2(0,  TexelSize.y)).rgb;
    float3 colorE = SceneColor.Sample(LinearSampler, uv + float2( TexelSize.x, 0)).rgb;
    float3 colorW = SceneColor.Sample(LinearSampler, uv + float2(-TexelSize.x, 0)).rgb;

    float lumaCenter = Luminance(colorCenter);
    float lumaN = Luminance(colorN);
    float lumaS = Luminance(colorS);
    float lumaE = Luminance(colorE);
    float lumaW = Luminance(colorW);

    float lumaMin = min(lumaCenter, min(min(lumaN, lumaS), min(lumaE, lumaW)));
    float lumaMax = max(lumaCenter, max(max(lumaN, lumaS), max(lumaE, lumaW)));
    float lumaRange = lumaMax - lumaMin;

    // Skip pixel if contrast is below threshold (flat area or too dark)
    if (lumaRange < max(EdgeThresholdMin, lumaMax * EdgeThreshold))
        return float4(colorCenter, 1.0);

    // Sample 4 diagonal neighbors for sub-pixel aliasing detection
    float3 colorNW = SceneColor.Sample(LinearSampler, uv + float2(-TexelSize.x, -TexelSize.y)).rgb;
    float3 colorNE = SceneColor.Sample(LinearSampler, uv + float2( TexelSize.x, -TexelSize.y)).rgb;
    float3 colorSW = SceneColor.Sample(LinearSampler, uv + float2(-TexelSize.x,  TexelSize.y)).rgb;
    float3 colorSE = SceneColor.Sample(LinearSampler, uv + float2( TexelSize.x,  TexelSize.y)).rgb;

    float lumaNW = Luminance(colorNW);
    float lumaNE = Luminance(colorNE);
    float lumaSW = Luminance(colorSW);
    float lumaSE = Luminance(colorSE);

    // Sub-pixel aliasing: how much does the center differ from its neighborhood average?
    float lumaAvg = (lumaN + lumaS + lumaE + lumaW) * 0.25;
    float subpixelOffset = saturate(abs(lumaAvg - lumaCenter) / lumaRange);
    subpixelOffset = smoothstep(0.0, 1.0, subpixelOffset);
    subpixelOffset = subpixelOffset * subpixelOffset * SubpixelQuality;

    // Determine edge direction: horizontal or vertical
    float edgeH = abs(lumaNW + lumaNE - 2.0 * lumaN)
                + abs(lumaW  + lumaE  - 2.0 * lumaCenter) * 2.0
                + abs(lumaSW + lumaSE - 2.0 * lumaS);
    float edgeV = abs(lumaNW + lumaSW - 2.0 * lumaW)
                + abs(lumaN  + lumaS  - 2.0 * lumaCenter) * 2.0
                + abs(lumaNE + lumaSE - 2.0 * lumaE);
    bool isHorizontal = (edgeH >= edgeV);

    // Step size along the edge normal (perpendicular to edge direction)
    float stepLength = isHorizontal ? TexelSize.y : TexelSize.x;

    // Choose the neighbor with higher contrast (which side of the edge we're on)
    float lumaPos = isHorizontal ? lumaS : lumaE;
    float lumaNeg = isHorizontal ? lumaN : lumaW;
    float gradPos = abs(lumaPos - lumaCenter);
    float gradNeg = abs(lumaNeg - lumaCenter);

    float lumaLocalAvg;
    if (gradPos >= gradNeg)
    {
        lumaLocalAvg = 0.5 * (lumaCenter + lumaPos);
    }
    else
    {
        stepLength = -stepLength;
        lumaLocalAvg = 0.5 * (lumaCenter + lumaNeg);
    }

    // Start at half-pixel offset from center in edge normal direction
    float2 edgeUV = uv;
    if (isHorizontal)
        edgeUV.y += stepLength * 0.5;
    else
        edgeUV.x += stepLength * 0.5;

    // Edge tangent direction (along the edge)
    float2 edgeStep = isHorizontal ? float2(TexelSize.x, 0) : float2(0, TexelSize.y);

    // Search along edge in both directions with progressive step sizes
    static const float SEARCH_STEPS[12] = { 1.0, 1.0, 1.0, 1.0, 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0 };

    float2 uvPos = edgeUV;
    float2 uvNeg = edgeUV;
    float lumaDeltaPos = 0;
    float lumaDeltaNeg = 0;
    bool reachedPos = false;
    bool reachedNeg = false;

    for (int i = 0; i < 12; i++)
    {
        if (!reachedPos)
        {
            uvPos += edgeStep * SEARCH_STEPS[i];
            lumaDeltaPos = Luminance(SceneColor.Sample(LinearSampler, uvPos).rgb) - lumaLocalAvg;
            reachedPos = abs(lumaDeltaPos) >= gradPos * 0.5;
        }
        if (!reachedNeg)
        {
            uvNeg -= edgeStep * SEARCH_STEPS[i];
            lumaDeltaNeg = Luminance(SceneColor.Sample(LinearSampler, uvNeg).rgb) - lumaLocalAvg;
            reachedNeg = abs(lumaDeltaNeg) >= gradNeg * 0.5;
        }
        if (reachedPos && reachedNeg) break;
    }

    // Compute distances to edge endpoints
    float distPos = isHorizontal ? (uvPos.x - uv.x) : (uvPos.y - uv.y);
    float distNeg = isHorizontal ? (uv.x - uvNeg.x) : (uv.y - uvNeg.y);
    float distMin = min(distPos, distNeg);
    float edgeLength = distPos + distNeg;

    // Determine the pixel offset along the edge normal
    float edgeOffset = -distMin / edgeLength + 0.5;

    // Reject if the center is on the wrong side of the edge
    bool isLumaCenterSmaller = lumaCenter < lumaLocalAvg;
    bool correctVariation = ((distPos < distNeg) ? lumaDeltaPos : lumaDeltaNeg) >= 0.0 != isLumaCenterSmaller;

    float finalOffset = correctVariation ? edgeOffset : 0.0;
    finalOffset = max(finalOffset, subpixelOffset);

    // Sample at the computed offset
    float2 finalUV = uv;
    if (isHorizontal)
        finalUV.y += finalOffset * stepLength;
    else
        finalUV.x += finalOffset * stepLength;

    float3 result = SceneColor.Sample(LinearSampler, finalUV).rgb;
    return float4(result, 1.0);
}
