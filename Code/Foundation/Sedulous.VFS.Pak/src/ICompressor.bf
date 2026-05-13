using System;

namespace Sedulous.VFS.Pak;

/// Stable codec identifier persisted in TOC entries. Values are part of the on-disk
/// format - never reassign an existing value, only add new ones.
public enum CompressionId : uint16
{
	/// No compression - stored bytes equal original bytes.
	None = 0,

	// Reserved for future codecs:
	// Zstd = 1,
	// LZ4  = 2,
}

/// Failure modes for compressor operations.
public enum CompressionError
{
	/// The compressed input was malformed or truncated.
	InvalidData,

	/// The destination buffer is smaller than the codec requires.
	OutputBufferTooSmall,

	/// The codec required for this entry is not registered on the mount.
	Unsupported
}

/// Pluggable compressor / decompressor.
///
/// Mounts hold a map of `CompressionId` -> `ICompressor` and look up the codec by the
/// ID stamped on each TOC entry. Builders pick one compressor when they construct the
/// pak. Adding a new codec is a matter of writing a new implementation and registering
/// it - the format itself doesn't change.
public interface ICompressor
{
	/// The codec identifier this compressor produces / consumes.
	CompressionId Id { get; }

	/// Worst-case compressed size for an input of `originalSize` bytes. Builders size
	/// their output buffer with this before calling `Compress`.
	int MaxCompressedSize(int originalSize);

	/// Compresses `src` into `dst`. Returns the number of bytes actually written to
	/// `dst`. The caller is responsible for sizing `dst` at least `MaxCompressedSize`.
	Result<int, CompressionError> Compress(Span<uint8> src, Span<uint8> dst);

	/// Decompresses `src` into `dst`. `dst.Length` must equal the original
	/// (uncompressed) size recorded in the TOC. Returns the number of bytes written.
	Result<int, CompressionError> Decompress(Span<uint8> src, Span<uint8> dst);
}
