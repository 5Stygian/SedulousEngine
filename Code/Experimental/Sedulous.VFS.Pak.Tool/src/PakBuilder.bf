using System;
using System.IO;
using System.Collections;
using Sedulous.VFS;
using Sedulous.VFS.Pak;

namespace Sedulous.VFS.Pak.Tool;

/// Offline pak builder. Accumulates entries in memory, then writes them to a pak
/// file in `PakFormat` layout.
///
/// Builders are single-use - construct, add entries, call `Write`, discard. The
/// builder owns copies of all added byte data until it's disposed.
///
/// Lives in `Sedulous.VFS.Pak.Tool` (not `Sedulous.VFS.Pak`) so runtime code never
/// pulls in the writer path.
public class PakBuilder
{
	private struct PendingEntry : IDisposable
	{
		public String Locator;
		public uint8[] Data;

		public void Dispose() mut
		{
			delete Locator;
			delete Data;
		}
	}

	private List<PendingEntry> mEntries = new .() ~ {
		for (var e in _) e.Dispose();
		delete _;
	};

	private ICompressor mCompressor;
	private PassthroughCompressor mDefaultCompressor = new .() ~ delete _;

	/// Creates a builder that compresses entries with `compressor`. Pass `null` to
	/// write entries uncompressed (CompressionId.None). The builder does not take
	/// ownership of the compressor - caller deletes it after `Write`.
	public this(ICompressor compressor = null)
	{
		mCompressor = compressor;
	}

	/// Appends an entry. `locator` is the mount-relative path the reader will use
	/// to look this entry up. The builder copies `data` immediately - the caller
	/// can free its source buffer right after.
	public void Add(StringView locator, Span<uint8> data)
	{
		let copy = new uint8[data.Length];
		if (data.Length > 0)
			Internal.MemCpy(copy.Ptr, data.Ptr, data.Length);

		let normalized = new String(locator);
		normalized.Replace('\\', '/');

		mEntries.Add(.() { Locator = normalized, Data = copy });
	}

	/// Number of entries queued for write.
	public int Count => mEntries.Count;

	/// Writes the pak file. The builder remains usable afterward - call `Write`
	/// again to produce another copy, or `Add` more entries first.
	public Result<void, MountError> Write(StringView outputPath)
	{
		let file = scope FileStream();
		if (file.Create(outputPath, .Write) case .Err)
			return .Err(.IOError);

		// 1. Reserve header space. Patched at the end once TocOffset/TocSize are known.
		PakFormat.Header headerStub = .();
		if (file.Write(headerStub) case .Err)
			return .Err(.IOError);

		// 2. Write data heap entry by entry, recording (offset, storedSize) per entry.
		let written = scope List<(uint64 Offset, uint64 StoredSize, CompressionId Compression)>();
		for (let entry in mEntries)
		{
			let offset = (uint64)file.Position;

			if (mCompressor != null && mCompressor.Id != .None)
			{
				let maxOut = mCompressor.MaxCompressedSize(entry.Data.Count);
				let outBuf = scope uint8[maxOut];

				let compressResult = mCompressor.Compress(
					Span<uint8>(entry.Data),
					Span<uint8>(&outBuf[0], maxOut));
				if (compressResult case .Err)
					return .Err(.IOError);

				let storedSize = compressResult.Value;
				if (file.TryWrite(.(&outBuf[0], storedSize)) case .Err)
					return .Err(.IOError);

				written.Add((offset, (uint64)storedSize, mCompressor.Id));
			}
			else
			{
				// No compression - write raw bytes.
				if (entry.Data.Count > 0)
				{
					if (file.TryWrite(Span<uint8>(entry.Data)) case .Err)
						return .Err(.IOError);
				}
				written.Add((offset, (uint64)entry.Data.Count, .None));
			}
		}

		// 3. TOC starts here.
		let tocOffset = (uint64)file.Position;
		for (int i = 0; i < mEntries.Count; i++)
		{
			let entry = mEntries[i];
			let w = written[i];
			let locator = entry.Locator;

			if (locator.Length > 65535)
				return .Err(.IOError); // locator too long for the format

			if (file.Write((uint16)locator.Length) case .Err) return .Err(.IOError);
			if (locator.Length > 0)
			{
				if (file.TryWrite(.((uint8*)locator.Ptr, locator.Length)) case .Err)
					return .Err(.IOError);
			}
			if (file.Write(w.Offset) case .Err) return .Err(.IOError);
			if (file.Write(w.StoredSize) case .Err) return .Err(.IOError);
			if (file.Write((uint64)entry.Data.Count) case .Err) return .Err(.IOError); // OriginalSize
			if (file.Write((uint16)w.Compression) case .Err) return .Err(.IOError);
		}
		let tocSize = (uint64)file.Position - tocOffset;

		// 4. Patch header in place.
		file.Position = 0;
		PakFormat.Header header = .()
		{
			Magic = PakFormat.Magic,
			Version = PakFormat.Version,
			EntryCount = (uint64)mEntries.Count,
			TocOffset = tocOffset,
			TocSize = tocSize,
		};
		if (file.Write(header) case .Err)
			return .Err(.IOError);

		return .Ok;
	}
}
