namespace Sedulous.Textures;

/// Describes the logical shape of a texture asset.
/// Used by TextureResource to indicate how pixel data should be
/// interpreted and uploaded to the GPU.
enum TextureShape
{
	/// Standard 2D texture (single image).
	Texture2D,
	/// 2D array texture (multiple layers, same dimensions).
	Texture2DArray,
	/// 3D volume texture.
	Texture3D,
	/// Cubemap (6 square faces: +X, -X, +Y, -Y, +Z, -Z).
	Cubemap,
	/// Array of cubemaps.
	CubemapArray
}

/// Texture filtering mode.
enum TextureFilter
{
	Nearest,
	Linear,
	MipmapNearest,
	MipmapLinear
}

/// Texture wrap mode.
enum TextureWrap
{
	Repeat,
	ClampToEdge,
	ClampToBorder,
	MirroredRepeat
}