using System;

namespace Sedulous.VFS.Pak;

/// On-disk layout for Sedulous pak files.
///
/// Binary layout (little-endian throughout):
///
///   [Header: 32 bytes]
///     uint32 Magic        = 'SPAK' (0x4B415053)
///     uint32 Version      = current PakFormat.Version
///     uint64 EntryCount
///     uint64 TocOffset    file offset of the TOC
///     uint64 TocSize      byte size of the TOC
///
///   [Data heap]
///     raw bytes, entries packed back-to-back. Each entry's bytes are written as
///     stored - if compressed, the compressed form; if not, the original.
///
///   [TOC: variable, located at Header.TocOffset]
///     For each entry, in arbitrary order:
///       uint16  LocatorLength   bytes (UTF-8, not null-terminated)
///       uint8[] Locator
///       uint64  Offset          into the file (points into the data heap)
///       uint64  StoredSize      bytes in the data heap (post-compression)
///       uint64  OriginalSize    bytes after decompression (== StoredSize when None)
///       uint16  Compression     CompressionId
///
/// Locators are mount-relative paths with forward slashes (same convention as
/// `IMount`). Path traversal (`..`) is the consumer's concern; the format itself
/// permits any byte string up to 65535 bytes.
public static class PakFormat
{
	/// Magic number written at the start of every pak file. ASCII "SPAK" in
	/// little-endian byte order so a hex dump reads naturally.
	public const uint32 Magic = 0x4B415053;

	/// Current format version. Mounts refuse to open paks whose version doesn't
	/// match - bump this when the layout changes incompatibly.
	public const uint32 Version = 1;

	/// Fixed-size header at the start of every pak file.
	[CRepr]
	public struct Header
	{
		public uint32 Magic;
		public uint32 Version;
		public uint64 EntryCount;
		public uint64 TocOffset;
		public uint64 TocSize;
	}
}
