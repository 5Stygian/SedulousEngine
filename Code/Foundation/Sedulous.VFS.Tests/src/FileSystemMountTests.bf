using System;
using System.IO;
using System.Collections;
using Sedulous.VFS;
using Sedulous.VFS.Disk;

namespace Sedulous.VFS.Tests;

class FileSystemMountTests
{
	// === Helpers ===

	private static void CreateTempRoot(String outPath)
	{
		let temp = scope String();
		Path.GetTempPath(temp);
		let unique = scope String();
		Guid.Create().ToString(unique);
		Path.InternalCombine(outPath, temp, "sedulous-vfs-tests-");
		outPath.Append(unique);
		Directory.CreateDirectory(outPath).IgnoreError();
	}

	private static void WriteFile(StringView path, StringView content)
	{
		let stream = scope FileStream();
		stream.Create(path, .Write).IgnoreError();
		stream.TryWrite(.((uint8*)content.Ptr, content.Length)).IgnoreError();
	}

	private static MemoryStream MakeMemoryStream(StringView content)
	{
		let stream = new MemoryStream();
		stream.TryWrite(.((uint8*)content.Ptr, content.Length)).IgnoreError();
		stream.Position = 0;
		return stream;
	}

	private static void ReadAll(Stream stream, String outContent)
	{
		uint8[256] buf = ?;
		while (true)
		{
			switch (stream.TryRead(.(&buf[0], 256)))
			{
			case .Ok(let n):
				if (n == 0) return;
				for (int i = 0; i < n; i++)
					outContent.Append((char8)buf[i]);
			case .Err: return;
			}
		}
	}

	// === Exists / Open ===

	[Test]
	public static void Exists_ReturnsTrueForExistingFile()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		WriteFile(scope $"{root}/hello.txt", "hi");

		let mount = scope FileSystemMount(root);
		Test.Assert(mount.Exists("hello.txt"));
		Test.Assert(!mount.Exists("nope.txt"));
	}

	[Test]
	public static void Open_ReadsFileContents()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		WriteFile(scope $"{root}/data.txt", "hello vfs");

		let mount = scope FileSystemMount(root);
		let stream = mount.Open("data.txt").Value;
		defer delete stream;

		let content = scope String();
		ReadAll(stream, content);
		Test.Assert(content == "hello vfs");
	}

	[Test]
	public static void Open_NotFoundReturnsError()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		let mount = scope FileSystemMount(root);
		Test.Assert(mount.Open("missing.txt") case .Err(.NotFound));
	}

	[Test]
	public static void Open_TwoConcurrentStreamsBothReadCorrectly()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		WriteFile(scope $"{root}/a.txt", "alpha");
		WriteFile(scope $"{root}/b.txt", "bravo");

		let mount = scope FileSystemMount(root);
		let sa = mount.Open("a.txt").Value; defer delete sa;
		let sb = mount.Open("b.txt").Value; defer delete sb;

		let ca = scope String(); ReadAll(sa, ca);
		let cb = scope String(); ReadAll(sb, cb);
		Test.Assert(ca == "alpha");
		Test.Assert(cb == "bravo");
	}

	// === Enumerate ===

	[Test]
	public static void Enumerate_ListsFilesAndDirs()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		WriteFile(scope $"{root}/a.txt", "a");
		WriteFile(scope $"{root}/b.txt", "b");
		Directory.CreateDirectory(scope $"{root}/sub").IgnoreError();
		WriteFile(scope $"{root}/sub/c.txt", "c");

		let mount = scope FileSystemMount(root);
		let entries = scope List<String>();
		defer { for (let s in entries) delete s; }
		mount.Enumerate("", entries);

		bool sawA = false, sawB = false, sawSub = false;
		for (let e in entries)
		{
			if (e == "a.txt") sawA = true;
			else if (e == "b.txt") sawB = true;
			else if (e == "sub/") sawSub = true;
		}
		Test.Assert(sawA);
		Test.Assert(sawB);
		Test.Assert(sawSub);
	}

	[Test]
	public static void Enumerate_NonExistentFolderReturnsEmpty()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		let mount = scope FileSystemMount(root);
		let entries = scope List<String>();
		defer { for (let s in entries) delete s; }
		mount.Enumerate("does/not/exist/", entries);
		Test.Assert(entries.Count == 0);
	}

	// === Save / Delete ===

	[Test]
	public static void Save_WritesNewFile()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		let mount = scope FileSystemMount(root);
		let source = MakeMemoryStream("written via mount");
		defer delete source;

		Test.Assert(mount.Save("created.txt", source) case .Ok);
		Test.Assert(mount.Exists("created.txt"));

		// Verify contents round-trip.
		let stream = mount.Open("created.txt").Value;
		defer delete stream;
		let content = scope String();
		ReadAll(stream, content);
		Test.Assert(content == "written via mount");
	}

	[Test]
	public static void Save_ReplacesExistingFile()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		WriteFile(scope $"{root}/file.txt", "old content");

		let mount = scope FileSystemMount(root);
		let source = MakeMemoryStream("brand new");
		defer delete source;

		Test.Assert(mount.Save("file.txt", source) case .Ok);

		let stream = mount.Open("file.txt").Value;
		defer delete stream;
		let content = scope String();
		ReadAll(stream, content);
		Test.Assert(content == "brand new");
	}

	[Test]
	public static void Save_EmptyDataCreatesEmptyFile()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		let mount = scope FileSystemMount(root);
		let source = scope MemoryStream();
		Test.Assert(mount.Save("empty.bin", source) case .Ok);
		Test.Assert(mount.Exists("empty.bin"));

		let stream = mount.Open("empty.bin").Value;
		defer delete stream;
		Test.Assert(stream.Length == 0);
	}

	[Test]
	public static void Save_CreatesIntermediateDirectories()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		let mount = scope FileSystemMount(root);
		let source = MakeMemoryStream("nested");
		defer delete source;

		Test.Assert(mount.Save("a/b/c/file.txt", source) case .Ok);
		Test.Assert(mount.Exists("a/b/c/file.txt"));
	}

	[Test]
	public static void Delete_RemovesFile()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		WriteFile(scope $"{root}/temp.txt", "x");

		let mount = scope FileSystemMount(root);
		Test.Assert(mount.Delete("temp.txt") case .Ok);
		Test.Assert(!mount.Exists("temp.txt"));
	}

	[Test]
	public static void Delete_NonExistentReturnsNotFound()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		let mount = scope FileSystemMount(root);
		Test.Assert(mount.Delete("absent.txt") case .Err(.NotFound));
	}

	[Test]
	public static void Open_AfterDeleteReturnsNotFound()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		WriteFile(scope $"{root}/temp.txt", "x");
		let mount = scope FileSystemMount(root);
		mount.Delete("temp.txt").IgnoreError();
		Test.Assert(mount.Open("temp.txt") case .Err(.NotFound));
	}

	// === Root path normalization ===

	[Test]
	public static void RootPath_TrailingSlashIsStripped()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		WriteFile(scope $"{root}/file.txt", "x");

		let rootWithSlash = scope String(root);
		rootWithSlash.Append("/");
		let mount = scope FileSystemMount(rootWithSlash);
		Test.Assert(mount.Exists("file.txt"));
	}

	[Test]
	public static void RootPath_BackslashesAreNormalized()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		Directory.CreateDirectory(scope $"{root}/sub").IgnoreError();
		WriteFile(scope $"{root}/sub/file.txt", "x");

		// Pass root with mixed separators.
		let mixedRoot = scope String(root);
		mixedRoot.Replace('/', '\\');
		let mount = scope FileSystemMount(mixedRoot);
		Test.Assert(mount.Exists("sub/file.txt"));
	}

	// === Capabilities ===

	[Test]
	public static void CapabilityChecks_FileSystemImplementsAll()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		IMount mount = scope FileSystemMount(root);
		Test.Assert(mount is IEnumerableMount);
		Test.Assert(mount is IWritableMount);
		Test.Assert(mount is IWatchableMount);
	}
}
