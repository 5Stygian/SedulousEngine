// SSAO Fragment Shader
// Screen-Space Ambient Occlusion with hemisphere sampling.
// Reads SceneDepth + SceneNormals, outputs R8 occlusion factor.
// See CONVENTIONS.md for shader rules.

#pragma pack_matrix(row_major)

cbuffer SSAOParams : register(b0)
{
    float4x4 ProjectionMatrix;
    float4x4 InvProjectionMatrix;
    float2 TexelSize;       // 1.0 / screenSize
    float Radius;           // world-space sampling radius
    float Intensity;        // occlusion strength
    float Bias;             // depth bias to prevent self-occlusion
    float NearPlane;
    float FarPlane;
    float _Pad;
};

// 16 hemisphere kernel samples (uploaded from CPU)
cbuffer SSAOKernel : register(b1)
{
    float4 Samples[16];
};

Texture2D DepthTexture : register(t0);
Texture2D NormalTexture : register(t1);
SamplerState PointSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

// Linearize depth from [0,1] NDC to view-space Z (positive distance from camera)
float LinearizeDepth(float d)
{
    // Reverse the projection: z_ndc = (far * near) / (far - d * (far - near))
    // For a standard perspective projection matrix.
    return (NearPlane * FarPlane) / (FarPlane - d * (FarPlane - NearPlane));
}

// Reconstruct view-space position from UV + depth
float3 ReconstructViewPos(float2 uv, float depth)
{
    float linearDepth = LinearizeDepth(depth);
    // UV to clip space
    float2 ndc = uv * 2.0 - 1.0;
    ndc.y = -ndc.y;
    // Unproject using inverse projection
    float4 clipPos = float4(ndc, depth, 1.0);
    float4 viewPos = mul(clipPos, InvProjectionMatrix);
    return viewPos.xyz / viewPos.w;
}

// Per-pixel pseudo-random rotation (avoids noise texture)
float2 RandomRotation(float2 uv)
{
    // Hash based on screen position for stable per-pixel rotation
    float noiseX = frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
    float noiseY = frac(sin(dot(uv, float2(93.9898, 67.345))) * 24634.6345);
    return normalize(float2(noiseX, noiseY) * 2.0 - 1.0);
}

float main(FragmentInput input) : SV_Target
{
    float2 uv = input.TexCoord;

    // Read depth and reconstruct view-space position
    float depth = DepthTexture.Sample(PointSampler, uv).r;
    if (depth >= 1.0) return 1.0; // sky - no occlusion

    float3 viewPos = ReconstructViewPos(uv, depth);

    // Read view-space normal (XY stored in RG16Float, reconstruct Z)
    float2 normalXY = NormalTexture.Sample(PointSampler, uv).rg;
    float3 viewNormal = float3(normalXY, sqrt(max(0.0, 1.0 - dot(normalXY, normalXY))));
    viewNormal = normalize(viewNormal);

    // Build TBN frame from normal + per-pixel random rotation
    float2 rotVec = RandomRotation(uv * float2(1.0 / TexelSize.x, 1.0 / TexelSize.y));
    float3 tangent = normalize(float3(rotVec.x, rotVec.y, 0.0) - viewNormal * dot(float3(rotVec.x, rotVec.y, 0.0), viewNormal));
    float3 bitangent = cross(viewNormal, tangent);
    float3x3 TBN = float3x3(tangent, bitangent, viewNormal);

    // Hemisphere sampling
    float occlusion = 0.0;
    int sampleCount = 16;

    for (int i = 0; i < sampleCount; i++)
    {
        // Orient sample to hemisphere via TBN
        float3 sampleDir = mul(Samples[i].xyz, TBN);
        float3 samplePos = viewPos + sampleDir * Radius;

        // Project sample to screen
        float4 offset = mul(float4(samplePos, 1.0), ProjectionMatrix);
        offset.xy /= offset.w;
        float2 sampleUV = offset.xy * 0.5 + 0.5;
        sampleUV.y = 1.0 - sampleUV.y;

        // Sample depth at projected position
        float sampleDepth = DepthTexture.Sample(PointSampler, sampleUV).r;
        float3 sampleViewPos = ReconstructViewPos(sampleUV, sampleDepth);

        // Range check: fade out occlusion from surfaces beyond the sampling radius
        float rangeCheck = smoothstep(0.0, 1.0, Radius / (abs(viewPos.z - sampleViewPos.z) + 0.0001));

        // Occlusion test: sample is occluded if it's behind the depth buffer surface
        // (closer to camera in view space means more negative Z or smaller linear depth)
        occlusion += (sampleViewPos.z >= samplePos.z + Bias ? 1.0 : 0.0) * rangeCheck;
    }

    occlusion = 1.0 - (occlusion / float(sampleCount));
    return pow(occlusion, Intensity);
}
