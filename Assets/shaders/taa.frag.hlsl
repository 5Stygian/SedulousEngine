// TAA Resolve Fragment Shader
// Temporal Anti-Aliasing: blends current jittered frame with reprojected history.
// Runs in HDR before tone mapping. See CONVENTIONS.md for shader rules.

#pragma pack_matrix(row_major)

cbuffer TAAParams : register(b0)
{
    float2 TexelSize;          // 1.0 / screenSize
    float BlendFactor;         // base history weight (0.95 = default)
    float HistoryValid;        // 0.0 = no valid history (first frame), 1.0 = valid
    float2 JitterOffset;       // current frame's jitter in clip space
    float2 PrevJitterOffset;   // previous frame's jitter in clip space
};

Texture2D CurrentColor : register(t0);
Texture2D HistoryColor : register(t1);
Texture2D MotionVectors : register(t2);
Texture2D DepthTexture : register(t3);
SamplerState PointSampler : register(s0);
SamplerState LinearSampler : register(s1);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

struct FragmentOutput
{
    float4 Color : SV_Target0;   // Post-process chain output
    float4 History : SV_Target1; // History buffer for next frame
};

float Luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

// Clip color toward AABB center instead of hard clamping.
// Produces smoother results at AABB boundaries (Pedersen 2016, INSIDE).
float3 ClipToAABB(float3 color, float3 aabbMin, float3 aabbMax)
{
    float3 center = (aabbMax + aabbMin) * 0.5;
    float3 extents = (aabbMax - aabbMin) * 0.5;
    float3 shift = color - center;
    float3 absUnit = abs(shift / max(extents, 0.0001));
    float maxUnit = max(max(absUnit.x, absUnit.y), absUnit.z);
    return maxUnit > 1.0 ? center + (shift / maxUnit) : color;
}

FragmentOutput main(FragmentInput input)
{
    float2 uv = input.TexCoord;

    // Sample current color
    float3 current = CurrentColor.Sample(PointSampler, uv).rgb;

    // Find closest depth in 3x3 neighborhood for stable motion vector selection.
    float closestDepth = 1.0;
    float2 closestUV = uv;

    for (int y = -1; y <= 1; y++)
    {
        for (int x = -1; x <= 1; x++)
        {
            float2 sampleUV = uv + float2(x, y) * TexelSize;
            float d = DepthTexture.Sample(PointSampler, sampleUV).r;
            if (d < closestDepth)
            {
                closestDepth = d;
                closestUV = sampleUV;
            }
        }
    }

    // Sample motion vector at closest-depth position and reproject
    float2 motion = MotionVectors.Sample(PointSampler, closestUV).rg;
    float2 historyUV = uv - motion;

    // Reject history if out of bounds or first frame
    if (HistoryValid < 0.5 ||
        any(historyUV < 0.0) || any(historyUV > 1.0))
    {
        FragmentOutput rejected;
        rejected.Color = float4(current, 1.0);
        rejected.History = float4(current, 1.0);
        return rejected;
    }

    // Sample history
    float3 history = HistoryColor.Sample(LinearSampler, historyUV).rgb;

    // 3x3 neighborhood min/max for box clamping
    float3 neighborMin = current;
    float3 neighborMax = current;

    for (int ny = -1; ny <= 1; ny++)
    {
        for (int nx = -1; nx <= 1; nx++)
        {
            if (nx == 0 && ny == 0) continue;
            float3 s = CurrentColor.Sample(PointSampler, uv + float2(nx, ny) * TexelSize).rgb;
            neighborMin = min(neighborMin, s);
            neighborMax = max(neighborMax, s);
        }
    }

    // Clip history to neighborhood AABB (soft clip toward center)
    history = ClipToAABB(history, neighborMin, neighborMax);

    // Luminance-adaptive blend factor (Lumix approach):
    // When current and history luminance match closely -> high blend (stable).
    // When they differ (specular flash, disocclusion) -> low blend (responsive).
    float lum0 = Luminance(current);
    float lum1 = Luminance(history);
    float lumaDiff = 1.0 - abs(lum0 - lum1) / max(lum0, max(lum1, 0.1));
    float blend = lerp(0.85, BlendFactor, saturate(lumaDiff * lumaDiff));

    // Blend
    float3 result = lerp(current, history, blend);

    FragmentOutput output;
    output.Color = float4(result, 1.0);
    output.History = float4(result, 1.0);
    return output;
}
