using System;
using System.IO;
using System.Collections;
using Sedulous.VFS;
using Sedulous.VFS.Pak;
using Sedulous.VFS.Pak.Tool;

namespace Sedulous.VFS.Tests;

class PakMountTests
{
	// === Helpers ===

	private static void TempPakPath(String outPath)
	{
		let temp = scope String();
		Path.GetTempPath(temp);
		let unique = scope String();
		Guid.Create().ToString(unique);
		Path.InternalCombine(outPath, temp, "sedulous-vfs-pak-");
		outPath.Append(unique);
		outPath.Append(".pak");
	}

	/// Heap-allocates a byte array. Caller must `defer delete` it.
	/// Use when the bytes are needed for later comparison.
	private static uint8[] Bytes(StringView s)
	{
		let arr = new uint8[s.Length];
		for (int i = 0; i < s.Length; i++)
			arr[i] = (uint8)s[i];
		return arr;
	}

	/// Adds an entry whose bytes are scope-allocated for the duration of the call.
	/// Use when the test only needs to put bytes into the builder and never
	/// reads them again - avoids the `let x = Bytes(...); defer delete x;` dance.
	private static void AddBytes(PakBuilder builder, StringView locator, StringView content)
	{
		let bytes = scope uint8[content.Length];
		for (int i = 0; i < content.Length; i++)
			bytes[i] = (uint8)content[i];
		builder.Add(locator, bytes); // uint8[] -> Span<uint8> implicit
	}

	private static void ReadAll(Stream stream, List<uint8> outBytes)
	{
		uint8[256] buf = ?;
		while (true)
		{
			switch (stream.TryRead(.(&buf[0], 256)))
			{
			case .Ok(let n):
				if (n == 0) return;
				for (int i = 0; i < n; i++)
					outBytes.Add(buf[i]);
			case .Err:
				return;
			}
		}
	}

	private static bool BytesEqual(Span<uint8> a, Span<uint8> b)
	{
		if (a.Length != b.Length) return false;
		for (int i = 0; i < a.Length; i++)
			if (a[i] != b[i]) return false;
		return true;
	}

	// === Roundtrip ===

	[Test]
	public static void Roundtrip_SingleEntry()
	{
		let pakPath = scope String();
		TempPakPath(pakPath);
		defer { File.Delete(pakPath).IgnoreError(); }

		let payload = Bytes("hello pak");
		defer delete payload;

		// Build
		{
			let builder = scope PakBuilder();
			builder.Add("hello.txt", payload);
			Test.Assert(builder.Write(pakPath) case .Ok);
		}

		// Mount
		let mountResult = PakMount.LoadFromFile(pakPath);
		Test.Assert(mountResult case .Ok);
		let mount = mountResult.Value;
		defer delete mount;

		Test.Assert(mount.Exists("hello.txt"));

		// Read
		let openResult = mount.Open("hello.txt");
		Test.Assert(openResult case .Ok);
		let stream = openResult.Value;
		defer delete stream;

		let read = scope List<uint8>();
		ReadAll(stream, read);
		Test.Assert(BytesEqual(read, payload));
	}

	[Test]
	public static void Roundtrip_MultipleEntries()
	{
		let pakPath = scope String();
		TempPakPath(pakPath);
		defer { File.Delete(pakPath).IgnoreError(); }

		let a = Bytes("alpha"); defer delete a;
		let b = Bytes("bravo beta"); defer delete b;
		let c = Bytes("charlie chunk"); defer delete c;

		let builder = scope PakBuilder();
		builder.Add("a.txt", a);
		builder.Add("sub/b.txt", b);
		builder.Add("sub/deeper/c.txt", c);
		Test.Assert(builder.Write(pakPath) case .Ok);

		let mountResult = PakMount.LoadFromFile(pakPath);
		Test.Assert(mountResult case .Ok);
		let mount = mountResult.Value;
		defer delete mount;

		void CheckEntry(StringView locator, Span<uint8> expected)
		{
			Test.Assert(mount.Exists(locator));
			let result = mount.Open(locator);
			Test.Assert(result case .Ok);
			let stream = result.Value;
			defer delete stream;
			let read = scope List<uint8>();
			ReadAll(stream, read);
			Test.Assert(BytesEqual(read, expected));
		}

		CheckEntry("a.txt", a);
		CheckEntry("sub/b.txt", b);
		CheckEntry("sub/deeper/c.txt", c);
	}

	[Test]
	public static void Roundtrip_EmptyEntry()
	{
		let pakPath = scope String();
		TempPakPath(pakPath);
		defer { File.Delete(pakPath).IgnoreError(); }

		let builder = scope PakBuilder();
		builder.Add("empty.bin", Span<uint8>());
		Test.Assert(builder.Write(pakPath) case .Ok);

		let mount = PakMount.LoadFromFile(pakPath).Value;
		defer delete mount;

		let stream = mount.Open("empty.bin").Value;
		defer delete stream;
		Test.Assert(stream.Length == 0);
	}

	[Test]
	public static void Roundtrip_LargeEntry()
	{
		// 256 KiB of pseudo-random bytes - enough to span many read buffers.
		let payload = new uint8[256 * 1024];
		defer delete payload;
		for (int i = 0; i < payload.Count; i++)
			payload[i] = (uint8)((i * 2654435761) >> 24);

		let pakPath = scope String();
		TempPakPath(pakPath);
		defer { File.Delete(pakPath).IgnoreError(); }

		let builder = scope PakBuilder();
		builder.Add("big.bin", payload);
		Test.Assert(builder.Write(pakPath) case .Ok);

		let mount = PakMount.LoadFromFile(pakPath).Value;
		defer delete mount;

		let stream = mount.Open("big.bin").Value;
		defer delete stream;

		let read = scope List<uint8>();
		ReadAll(stream, read);
		Test.Assert(BytesEqual(read, payload));
	}

	[Test]
	public static void Open_MissingEntryReturnsNotFound()
	{
		let pakPath = scope String();
		TempPakPath(pakPath);
		defer { File.Delete(pakPath).IgnoreError(); }

		let builder = scope PakBuilder();
		AddBytes(builder, "present.txt", "x");
		Test.Assert(builder.Write(pakPath) case .Ok);

		let mount = PakMount.LoadFromFile(pakPath).Value;
		defer delete mount;

		Test.Assert(mount.Open("absent.txt") case .Err(.NotFound));
	}

	[Test]
	public static void OpensReopenFile_TwoStreamsAtOnce()
	{
		// Validates the reopen-per-Open policy: two concurrent streams can both
		// read without sharing a seek lock or stepping on each other.
		let pakPath = scope String();
		TempPakPath(pakPath);
		defer { File.Delete(pakPath).IgnoreError(); }

		let a = Bytes("alpha");          defer delete a;
		let b = Bytes("bravo and more"); defer delete b;

		let builder = scope PakBuilder();
		builder.Add("a.txt", a);
		builder.Add("b.txt", b);
		Test.Assert(builder.Write(pakPath) case .Ok);

		let mount = PakMount.LoadFromFile(pakPath).Value;
		defer delete mount;

		let sa = mount.Open("a.txt").Value; defer delete sa;
		let sb = mount.Open("b.txt").Value; defer delete sb;

		let ra = scope List<uint8>(); ReadAll(sa, ra);
		let rb = scope List<uint8>(); ReadAll(sb, rb);

		Test.Assert(BytesEqual(ra, a));
		Test.Assert(BytesEqual(rb, b));
	}

	// === Enumerate ===

	[Test]
	public static void Enumerate_RootListsFilesAndDirs()
	{
		let pakPath = scope String();
		TempPakPath(pakPath);
		defer { File.Delete(pakPath).IgnoreError(); }

		let builder = scope PakBuilder();
		AddBytes(builder, "a.txt", "a");
		AddBytes(builder, "sub/b.txt", "b");
		AddBytes(builder, "sub/c.txt", "c");
		Test.Assert(builder.Write(pakPath) case .Ok);

		let mount = PakMount.LoadFromFile(pakPath).Value;
		defer delete mount;

		let entries = scope List<String>();
		defer { for (let s in entries) delete s; }
		mount.Enumerate("", entries);

		bool sawA = false, sawSub = false;
		int subCount = 0;
		for (let e in entries)
		{
			if (e == "a.txt") sawA = true;
			else if (e == "sub/") { sawSub = true; subCount++; }
		}
		Test.Assert(sawA);
		Test.Assert(sawSub);
		Test.Assert(subCount == 1);
	}

	[Test]
	public static void Enumerate_SubfolderListsDirectChildren()
	{
		let pakPath = scope String();
		TempPakPath(pakPath);
		defer { File.Delete(pakPath).IgnoreError(); }

		let builder = scope PakBuilder();
		AddBytes(builder, "sub/b.txt", "b");
		AddBytes(builder, "sub/c.txt", "c");
		AddBytes(builder, "sub/deeper/d.txt", "d");
		Test.Assert(builder.Write(pakPath) case .Ok);

		let mount = PakMount.LoadFromFile(pakPath).Value;
		defer delete mount;

		let entries = scope List<String>();
		defer { for (let s in entries) delete s; }
		mount.Enumerate("sub/", entries);

		bool sawB = false, sawC = false, sawDeeper = false;
		for (let e in entries)
		{
			if (e == "sub/b.txt") sawB = true;
			else if (e == "sub/c.txt") sawC = true;
			else if (e == "sub/deeper/") sawDeeper = true;
		}
		Test.Assert(sawB);
		Test.Assert(sawC);
		Test.Assert(sawDeeper);
	}

	// === Format validation ===

	[Test]
	public static void Load_BadMagicReturnsError()
	{
		let pakPath = scope String();
		TempPakPath(pakPath);
		defer { File.Delete(pakPath).IgnoreError(); }

		// Write garbage where a pak should be.
		{
			let f = scope FileStream();
			Test.Assert(f.Create(pakPath, .Write) case .Ok);
			uint8[32] garbage = ?;
			for (int i = 0; i < 32; i++) garbage[i] = (uint8)i;
			f.TryWrite(.(&garbage[0], 32)).IgnoreError();
		}

		Test.Assert(PakMount.LoadFromFile(pakPath) case .Err);
	}

	[Test]
	public static void Load_TruncatedFileReturnsError()
	{
		let pakPath = scope String();
		TempPakPath(pakPath);
		defer { File.Delete(pakPath).IgnoreError(); }

		// File with only 4 bytes - not even a header.
		{
			let f = scope FileStream();
			Test.Assert(f.Create(pakPath, .Write) case .Ok);
			uint8[4] tiny = .(0x53, 0x50, 0x41, 0x4B); // 'SPAK'
			f.TryWrite(.(&tiny[0], 4)).IgnoreError();
		}

		Test.Assert(PakMount.LoadFromFile(pakPath) case .Err);
	}

	[Test]
	public static void Load_NonExistentReturnsNotFound()
	{
		let path = scope String();
		Path.GetTempPath(path);
		path.Append("sedulous-vfs-no-such-pak-");
		Guid.Create().ToString(path);
		path.Append(".pak");

		Test.Assert(PakMount.LoadFromFile(path) case .Err(.NotFound));
	}

	// === Compression ===

	[Test]
	public static void Open_UnknownCompressionReturnsNotSupported()
	{
		// Hand-craft a pak whose only entry claims CompressionId = 99 (unsupported).
		let pakPath = scope String();
		TempPakPath(pakPath);
		defer { File.Delete(pakPath).IgnoreError(); }

		{
			let f = scope FileStream();
			Test.Assert(f.Create(pakPath, .Write) case .Ok);

			// Data heap: 4 bytes of payload at offset = 32 (right after header).
			uint8[4] payload = .((.)'A', (.)'B', (.)'C', (.)'D');

			// Header stub - patched at end.
			PakFormat.Header headerStub = .();
			f.Write(headerStub).IgnoreError();

			// Data heap
			let dataOffset = (uint64)f.Position;
			f.TryWrite(.(&payload[0], 4)).IgnoreError();

			// TOC: one entry, locator "x", claims CompressionId 99.
			let tocOffset = (uint64)f.Position;
			f.Write((uint16)1).IgnoreError();
			f.TryWrite(.((uint8*)"x", 1)).IgnoreError();
			f.Write((uint64)dataOffset).IgnoreError();
			f.Write((uint64)4).IgnoreError();
			f.Write((uint64)4).IgnoreError();
			f.Write((uint16)99).IgnoreError();
			let tocSize = (uint64)f.Position - tocOffset;

			f.Position = 0;
			PakFormat.Header header = .()
			{
				Magic = PakFormat.Magic,
				Version = PakFormat.Version,
				EntryCount = 1,
				TocOffset = tocOffset,
				TocSize = tocSize,
			};
			f.Write(header).IgnoreError();
		}

		let mount = PakMount.LoadFromFile(pakPath).Value;
		defer delete mount;
		Test.Assert(mount.Open("x") case .Err(.NotSupported));
	}

	/// A test compressor that XORs each byte with 0x55. Easy to validate manually.
	class XorCompressor : ICompressor
	{
		// Hijacks CompressionId.None+1 - never reuse this for a real codec.
		public CompressionId Id => (CompressionId)42;
		public int MaxCompressedSize(int originalSize) => originalSize;

		public Result<int, CompressionError> Compress(Span<uint8> src, Span<uint8> dst)
		{
			if (dst.Length < src.Length) return .Err(.OutputBufferTooSmall);
			for (int i = 0; i < src.Length; i++)
				dst[i] = src[i] ^ 0x55;
			return .Ok(src.Length);
		}

		public Result<int, CompressionError> Decompress(Span<uint8> src, Span<uint8> dst)
		{
			if (dst.Length < src.Length) return .Err(.OutputBufferTooSmall);
			for (int i = 0; i < src.Length; i++)
				dst[i] = src[i] ^ 0x55;
			return .Ok(src.Length);
		}
	}

	[Test]
	public static void PluggableCompressor_RoundtripsBytes()
	{
		let pakPath = scope String();
		TempPakPath(pakPath);
		defer { File.Delete(pakPath).IgnoreError(); }

		let codec = scope XorCompressor();
		let payload = Bytes("the quick brown fox jumps over the lazy dog");
		defer delete payload;

		// Build with the XOR codec.
		{
			let builder = scope PakBuilder(codec);
			builder.Add("phrase.txt", payload);
			Test.Assert(builder.Write(pakPath) case .Ok);
		}

		// Mount and register the codec so the mount can decompress.
		let mount = PakMount.LoadFromFile(pakPath).Value;
		defer delete mount;
		mount.RegisterCompressor(codec);

		let stream = mount.Open("phrase.txt").Value;
		defer delete stream;
		let read = scope List<uint8>();
		ReadAll(stream, read);
		Test.Assert(BytesEqual(read, payload));
	}

	[Test]
	public static void PluggableCompressor_UnregisteredOnLoadReturnsNotSupported()
	{
		// Build with the XOR codec but DON'T register it on the mount - simulates
		// the case where a pak built with a future codec is loaded by an old reader.
		let pakPath = scope String();
		TempPakPath(pakPath);
		defer { File.Delete(pakPath).IgnoreError(); }

		let codec = scope XorCompressor();
		let payload = Bytes("compressed data");
		defer delete payload;

		let builder = scope PakBuilder(codec);
		builder.Add("data.bin", payload);
		Test.Assert(builder.Write(pakPath) case .Ok);

		let mount = PakMount.LoadFromFile(pakPath).Value;
		defer delete mount;
		// No RegisterCompressor call - mount only knows about Passthrough.

		Test.Assert(mount.Open("data.bin") case .Err(.NotSupported));
	}

	// === Locator handling ===

	[Test]
	public static void BackslashesInLocatorAreNormalized()
	{
		let pakPath = scope String();
		TempPakPath(pakPath);
		defer { File.Delete(pakPath).IgnoreError(); }

		let builder = scope PakBuilder();
		AddBytes(builder, @"sub\nested.txt", "x");
		Test.Assert(builder.Write(pakPath) case .Ok);

		let mount = PakMount.LoadFromFile(pakPath).Value;
		defer delete mount;

		// Builder normalized to '/', so the lookup uses '/'.
		Test.Assert(mount.Exists("sub/nested.txt"));
	}

	// === Capabilities ===

	[Test]
	public static void CapabilityChecks_PakIsReadAndEnumerateOnly()
	{
		let pakPath = scope String();
		TempPakPath(pakPath);
		defer { File.Delete(pakPath).IgnoreError(); }

		let builder = scope PakBuilder();
		AddBytes(builder, "x.txt", "x");
		Test.Assert(builder.Write(pakPath) case .Ok);

		IMount mount = PakMount.LoadFromFile(pakPath).Value;
		defer delete mount;

		Test.Assert(mount is IEnumerableMount);
		Test.Assert(!(mount is IWritableMount));
		Test.Assert(!(mount is IWatchableMount));
	}
}
