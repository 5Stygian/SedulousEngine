// Compute Skinning Shader
// Transforms skinned vertices (72 bytes) into standard mesh vertices (48 bytes).
// Blends 4 bone matrices per vertex. Bone indices packed as 4x uint16 in 2x uint32.

#pragma pack_matrix(row_major)

cbuffer SkinningParams : register(b0)
{
    uint VertexCount;
    uint BoneCount;
    uint _Pad0;
    uint _Pad1;
};

// Bone matrices: current frame (BoneCount matrices), then previous frame (BoneCount matrices).
// float4 rows instead of float4x4 - see CONVENTIONS.md (StructuredBuffer matrix layout).
struct BoneMatrix
{
    float4 Row0, Row1, Row2, Row3;
};
StructuredBuffer<BoneMatrix> BoneMatrices : register(t0);

// Source vertices (72 bytes each) - read as raw bytes
ByteAddressBuffer SourceVertices : register(t1);

// Output vertices (48 bytes each) - write as raw bytes
RWByteAddressBuffer OutputVertices : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint vertexIndex = dtid.x;
    if (vertexIndex >= VertexCount)
        return;

    // Read source vertex (72 bytes)
    // Layout: Position(12) Normal(12) TexCoord(8) Color(4) Tangent(12) Joints(8) Weights(16)
    uint srcOffset = vertexIndex * 72;

    float3 position = asfloat(SourceVertices.Load3(srcOffset));
    float3 normal = asfloat(SourceVertices.Load3(srcOffset + 12));
    float2 texCoord = asfloat(SourceVertices.Load2(srcOffset + 24));
    uint color = SourceVertices.Load(srcOffset + 32);
    float3 tangent = asfloat(SourceVertices.Load3(srcOffset + 36));

    // Unpack bone indices: 4x uint16 packed in 2x uint32
    uint joints01 = SourceVertices.Load(srcOffset + 48);
    uint joints23 = SourceVertices.Load(srcOffset + 52);
    uint4 jointIndices = uint4(
        joints01 & 0xFFFF,
        (joints01 >> 16) & 0xFFFF,
        joints23 & 0xFFFF,
        (joints23 >> 16) & 0xFFFF
    );

    float4 weights = asfloat(SourceVertices.Load4(srcOffset + 56));

    // Reconstruct and blend bone matrices from float4 rows
    BoneMatrix bx = BoneMatrices[jointIndices.x];
    BoneMatrix by = BoneMatrices[jointIndices.y];
    BoneMatrix bz = BoneMatrices[jointIndices.z];
    BoneMatrix bw = BoneMatrices[jointIndices.w];

    float4x4 skinMatrix = float4x4(
        bx.Row0 * weights.x + by.Row0 * weights.y + bz.Row0 * weights.z + bw.Row0 * weights.w,
        bx.Row1 * weights.x + by.Row1 * weights.y + bz.Row1 * weights.z + bw.Row1 * weights.w,
        bx.Row2 * weights.x + by.Row2 * weights.y + bz.Row2 * weights.z + bw.Row2 * weights.w,
        bx.Row3 * weights.x + by.Row3 * weights.y + bz.Row3 * weights.z + bw.Row3 * weights.w
    );

    // Transform position (as point, w=1)
    float3 skinnedPos = mul(float4(position, 1.0), skinMatrix).xyz;

    // Transform normal and tangent (as direction, w=0), then normalize
    float3 skinnedNormal = normalize(mul(float4(normal, 0.0), skinMatrix).xyz);
    float3 skinnedTangent = normalize(mul(float4(tangent, 0.0), skinMatrix).xyz);

    // Write output vertex (48 bytes)
    // Layout: Position(12) Normal(12) TexCoord(8) Color(4) Tangent(12)
    uint dstOffset = vertexIndex * 48;

    OutputVertices.Store3(dstOffset, asuint(skinnedPos));
    OutputVertices.Store3(dstOffset + 12, asuint(skinnedNormal));
    OutputVertices.Store2(dstOffset + 24, asuint(texCoord));
    OutputVertices.Store(dstOffset + 32, color);
    OutputVertices.Store3(dstOffset + 36, asuint(skinnedTangent));
}
