// Entity pick vertex shader
// Transforms position and passes entity index to fragment shader.
// Outputs entity index encoded as RGBA8 color for GPU picking.

#pragma pack_matrix(row_major)

cbuffer SceneUniforms : register(b0, space0)
{
    float4x4 ViewMatrix;
    float4x4 ProjectionMatrix;
    float4x4 ViewProjectionMatrix;
};

// Set 3: Per-draw data (world matrix + entity index)
cbuffer ObjectUniforms : register(b0, space3)
{
    float4x4 WorldMatrix;
    float4x4 PrevWorldMatrix;
    uint EntityIndex;
};

struct VertexInput
{
    float3 Position : TEXCOORD0;
    float3 Normal : TEXCOORD1;
    float2 TexCoord : TEXCOORD2;
    float4 Color : TEXCOORD3;
    float3 Tangent : TEXCOORD4;
};

struct VertexOutput
{
    float4 Position : SV_Position;
    nointerpolation uint EntityIndex : TEXCOORD0;
};

VertexOutput main(VertexInput input)
{
    VertexOutput output;
    float4 worldPos = mul(float4(input.Position, 1.0), WorldMatrix);
    output.Position = mul(worldPos, ViewProjectionMatrix);
    output.EntityIndex = EntityIndex;
    return output;
}
