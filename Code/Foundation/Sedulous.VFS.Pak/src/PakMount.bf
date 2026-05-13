using System;
using System.IO;
using System.Collections;
using Sedulous.VFS;

namespace Sedulous.VFS.Pak;

/// Read-only mount backed by a Sedulous pak file. The pak's TOC is loaded into
/// memory at construction; entry bytes are read on demand via fresh `FileStream`
/// opens (the reopen-per-Open policy - simple, no shared seek lock, fans out across
/// cores).
///
/// Implements `IMount` and `IEnumerableMount`. Notably absent: `IWritableMount`
/// (paks are immutable once built) and `IWatchableMount` (the pak file might be
/// replaced wholesale but we don't track that). Trying to write to a pak is a
/// compile-time mismatch, not a runtime error.
///
/// Capability matrix:
///   - Read    : ✓
///   - List    : ✓
///   - Watch   : ✗
///   - Write   : ✗
public class PakMount : IMount, IEnumerableMount
{
	private struct Entry
	{
		public uint64 Offset;
		public uint64 StoredSize;
		public uint64 OriginalSize;
		public CompressionId Compression;
	}

	private String mPakPath = new .() ~ delete _;
	private Dictionary<String, Entry> mEntries = new .() ~ {
		for (let kv in _) delete kv.key;
		delete _;
	};
	private Dictionary<CompressionId, ICompressor> mCompressors = new .() ~ delete _;
	private PassthroughCompressor mPassthrough = new .() ~ delete _;

	private this()
	{
		mCompressors[.None] = mPassthrough;
	}

	/// Loads and validates the pak at `path`. Reads the header + TOC; returns
	/// errors for missing files, bad magic, or unsupported versions.
	public static Result<PakMount, MountError> LoadFromFile(StringView path)
	{
		let mount = new PakMount();
		if (mount.LoadTocFromFile(path) case .Err(let err))
		{
			delete mount;
			return .Err(err);
		}
		return .Ok(mount);
	}

	/// Registers an additional codec. The mount needs a registered `ICompressor`
	/// for every `CompressionId` that appears in its TOC, or `Open` returns
	/// `.NotSupported`. The passthrough codec (`CompressionId.None`) is preinstalled.
	///
	/// The mount does not take ownership - caller deletes the compressor after the
	/// mount is gone.
	public void RegisterCompressor(ICompressor compressor)
	{
		mCompressors[compressor.Id] = compressor;
	}

	// === IMount ===

	public bool Exists(StringView locator)
	{
		return TryGetEntry(locator, ?);
	}

	public Result<Stream, MountError> Open(StringView locator)
	{
		Entry entry;
		if (!TryGetEntry(locator, out entry))
			return .Err(.NotFound);

		let compressor = GetCompressor(entry.Compression);
		if (compressor == null)
			return .Err(.NotSupported);

		// Reopen the pak file for this read. Cheap on Windows/Linux; trades a
		// handle for not needing a seek lock across threads.
		let file = scope FileStream();
		if (file.Open(mPakPath, .Read, .Read) case .Err)
			return .Err(.IOError);

		file.Position = (int64)entry.Offset;
		let stored = new uint8[(int)entry.StoredSize];
		if (file.TryRead(.(stored.Ptr, stored.Count)) case .Err)
		{
			delete stored;
			return .Err(.IOError);
		}

		// Fast path for uncompressed entries: hand the buffer straight to the
		// stream. Avoids the copy a roundtrip through `Decompress` would do.
		if (entry.Compression == .None)
			return .Ok(new PakEntryStream(stored));

		let decompressed = new uint8[(int)entry.OriginalSize];
		let result = compressor.Decompress(.(stored.Ptr, stored.Count),
			.(decompressed.Ptr, decompressed.Count));
		delete stored;
		if (result case .Err)
		{
			delete decompressed;
			return .Err(.IOError);
		}

		return .Ok(new PakEntryStream(decompressed));
	}

	// === IEnumerableMount ===

	public void Enumerate(StringView folderLocator, List<String> outEntries)
	{
		let prefixLen = folderLocator.Length;
		let seenDirs = scope List<String>();
		defer { for (let s in seenDirs) delete s; }

		for (let kv in mEntries)
		{
			let key = StringView(kv.key);
			if (prefixLen > 0 && !key.StartsWith(folderLocator))
				continue;

			let remainder = key[prefixLen...];
			let slashIdx = remainder.IndexOf('/');
			if (slashIdx < 0)
			{
				let s = new String();
				s.Append(folderLocator);
				s.Append(remainder);
				outEntries.Add(s);
			}
			else
			{
				let dirName = remainder[0..<slashIdx];
				bool seen = false;
				for (let prev in seenDirs)
				{
					if (StringView(prev) == dirName) { seen = true; break; }
				}
				if (!seen)
				{
					seenDirs.Add(new String(dirName));
					let s = new String();
					s.Append(folderLocator);
					s.Append(dirName);
					s.Append('/');
					outEntries.Add(s);
				}
			}
		}
	}

	// === Internal ===

	private bool TryGetEntry(StringView locator, out Entry entry)
	{
		for (let kv in mEntries)
		{
			if (StringView(kv.key) == locator)
			{
				entry = kv.value;
				return true;
			}
		}
		entry = default;
		return false;
	}

	private ICompressor GetCompressor(CompressionId id)
	{
		if (mCompressors.TryGetValue(id, let c))
			return c;
		return null;
	}

	private Result<void, MountError> LoadTocFromFile(StringView path)
	{
		let file = scope FileStream();
		if (file.Open(path, .Read, .Read) case .Err(let err))
		{
			switch (err)
			{
			case .NotFound: return .Err(.NotFound);
			case .SharingViolation: return .Err(.AccessDenied);
			default: return .Err(.IOError);
			}
		}

		// Header
		let headerResult = file.Read<PakFormat.Header>();
		if (headerResult case .Err)
			return .Err(.IOError);
		let header = headerResult.Value;

		if (header.Magic != PakFormat.Magic)
			return .Err(.IOError);     // corrupt or not a pak
		if (header.Version != PakFormat.Version)
			return .Err(.NotSupported); // wrong version

		// Sanity: TOC must be inside the file.
		let fileLen = (uint64)file.Length;
		if (header.TocOffset >= fileLen)
			return .Err(.IOError);
		if (header.TocOffset + header.TocSize > fileLen)
			return .Err(.IOError);

		// TOC
		file.Position = (int64)header.TocOffset;
		for (uint64 i = 0; i < header.EntryCount; i++)
		{
			// Locator length
			let lenRes = file.Read<uint16>();
			if (lenRes case .Err) return .Err(.IOError);
			let locLen = lenRes.Value;

			// Locator bytes
			let locBuf = scope uint8[locLen];
			if (locLen > 0)
			{
				if (file.TryRead(.(locBuf.Ptr, locLen)) case .Err)
					return .Err(.IOError);
			}
			let locator = new String((char8*)locBuf.Ptr, locLen);

			// Entry fields
			Entry entry = .();
			if (file.Read<uint64>() case .Ok(let off))   entry.Offset = off;           else { delete locator; return .Err(.IOError); }
			if (file.Read<uint64>() case .Ok(let sto))   entry.StoredSize = sto;       else { delete locator; return .Err(.IOError); }
			if (file.Read<uint64>() case .Ok(let orig))  entry.OriginalSize = orig;    else { delete locator; return .Err(.IOError); }
			if (file.Read<uint16>() case .Ok(let comp))  entry.Compression = (.)comp;  else { delete locator; return .Err(.IOError); }

			// Sanity check: entry must lie inside the file before the TOC.
			if (entry.Offset + entry.StoredSize > header.TocOffset)
			{
				delete locator;
				return .Err(.IOError);
			}

			mEntries[locator] = entry;
		}

		mPakPath.Set(path);
		return .Ok;
	}
}
