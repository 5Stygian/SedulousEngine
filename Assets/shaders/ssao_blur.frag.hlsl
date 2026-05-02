// SSAO Bilateral Blur Fragment Shader
// Smooths the raw AO texture while preserving depth edges.
// 4x4 box filter weighted by depth similarity.

cbuffer BlurParams : register(b0)
{
    float2 TexelSize;
    float DepthThreshold;  // max depth difference before weight drops to zero
    float _Pad;
};

Texture2D AOTexture : register(t0);
Texture2D DepthTexture : register(t1);
SamplerState PointSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

float main(FragmentInput input) : SV_Target
{
    float2 uv = input.TexCoord;

    float centerDepth = DepthTexture.Sample(PointSampler, uv).r;
    float centerAO = AOTexture.Sample(PointSampler, uv).r;

    float totalAO = 0.0;
    float totalWeight = 0.0;

    for (int y = -2; y <= 2; y++)
    {
        for (int x = -2; x <= 2; x++)
        {
            float2 sampleUV = uv + float2(x, y) * TexelSize;
            float sampleAO = AOTexture.Sample(PointSampler, sampleUV).r;
            float sampleDepth = DepthTexture.Sample(PointSampler, sampleUV).r;

            // Bilateral weight: reject samples with large depth difference
            float depthDiff = abs(centerDepth - sampleDepth);
            float w = exp(-depthDiff * depthDiff / (DepthThreshold * DepthThreshold + 0.0001));

            totalAO += sampleAO * w;
            totalWeight += w;
        }
    }

    return totalAO / max(totalWeight, 0.0001);
}
