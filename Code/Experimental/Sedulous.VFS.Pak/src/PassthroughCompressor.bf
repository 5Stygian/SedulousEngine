using System;

namespace Sedulous.VFS.Pak;

/// Identity codec: stored bytes equal original bytes. Always registered with every
/// `PakMount` so paks built without explicit compression still load.
///
/// Real codecs (zstd, LZ4) plug in alongside this one by implementing `ICompressor`
/// and being registered via `PakMount.RegisterCompressor`.
public class PassthroughCompressor : ICompressor
{
	public CompressionId Id => .None;

	public int MaxCompressedSize(int originalSize) => originalSize;

	public Result<int, CompressionError> Compress(Span<uint8> src, Span<uint8> dst)
	{
		if (dst.Length < src.Length)
			return .Err(.OutputBufferTooSmall);
		Internal.MemCpy(dst.Ptr, src.Ptr, src.Length);
		return .Ok(src.Length);
	}

	public Result<int, CompressionError> Decompress(Span<uint8> src, Span<uint8> dst)
	{
		if (dst.Length < src.Length)
			return .Err(.OutputBufferTooSmall);
		Internal.MemCpy(dst.Ptr, src.Ptr, src.Length);
		return .Ok(src.Length);
	}
}
