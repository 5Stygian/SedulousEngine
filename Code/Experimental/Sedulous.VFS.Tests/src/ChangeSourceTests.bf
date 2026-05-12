using System;
using System.IO;
using System.Threading;
using System.Collections;
using Sedulous.VFS;
using Sedulous.VFS.Disk;

namespace Sedulous.VFS.Tests;

class ChangeSourceTests
{
	private static void CreateTempRoot(String outPath)
	{
		let temp = scope String();
		Path.GetTempPath(temp);
		let unique = scope String();
		Guid.Create().ToString(unique);
		Path.InternalCombine(outPath, temp, "sedulous-vfs-cs-");
		outPath.Append(unique);
		Directory.CreateDirectory(outPath).IgnoreError();
	}

	private static void WriteFile(StringView path, StringView content)
	{
		let stream = scope FileStream();
		stream.Create(path, .Write).IgnoreError();
		stream.TryWrite(.((uint8*)content.Ptr, content.Length)).IgnoreError();
	}

	private static FileSystemChangeSource MakeImmediateChangeSource(FileSystemMount mount)
	{
		// Cast through the interface to get a typed source, then force the poll
		// interval to zero so tests don't have to sleep.
		let cs = mount.ChangeSource as FileSystemChangeSource;
		cs.MinPollIntervalSeconds = 0;
		return cs;
	}

	[Test]
	public static void Poll_DetectsModification()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		let filePath = scope $"{root}/file.txt";
		WriteFile(filePath, "v1");

		let mount = scope FileSystemMount(root);
		let cs = MakeImmediateChangeSource(mount);
		cs.Track("file.txt");

		// File mtime resolution on Windows is ~1ms; on FAT it's 2s. We bump the
		// mtime explicitly via a short sleep + rewrite to make this stable.
		Thread.Sleep(50);
		WriteFile(filePath, "v2 longer content");

		let changes = scope List<String>();
		defer { for (let s in changes) delete s; }

		Test.Assert(cs.Poll(changes));
		Test.Assert(changes.Count == 1);
		Test.Assert(changes[0] == "file.txt");
	}

	[Test]
	public static void Poll_ReturnsFalseWithNoChanges()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		WriteFile(scope $"{root}/file.txt", "v1");

		let mount = scope FileSystemMount(root);
		let cs = MakeImmediateChangeSource(mount);
		cs.Track("file.txt");

		// Drain the initial poll (no change yet vs the recorded mtime).
		let changes = scope List<String>();
		defer { for (let s in changes) delete s; }
		cs.Poll(changes);
		for (let s in changes) delete s;
		changes.Clear();

		// Subsequent poll with no modifications.
		Test.Assert(!cs.Poll(changes));
		Test.Assert(changes.Count == 0);
	}

	[Test]
	public static void Untrack_StopsReportingChanges()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		let filePath = scope $"{root}/file.txt";
		WriteFile(filePath, "v1");

		let mount = scope FileSystemMount(root);
		let cs = MakeImmediateChangeSource(mount);
		cs.Track("file.txt");
		cs.Untrack("file.txt");

		Thread.Sleep(50);
		WriteFile(filePath, "v2 changed content");

		let changes = scope List<String>();
		defer { for (let s in changes) delete s; }
		Test.Assert(!cs.Poll(changes));
	}

	[Test]
	public static void Poll_DetectsMultipleChangesInOneCall()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		WriteFile(scope $"{root}/a.txt", "a");
		WriteFile(scope $"{root}/b.txt", "b");

		let mount = scope FileSystemMount(root);
		let cs = MakeImmediateChangeSource(mount);
		cs.Track("a.txt");
		cs.Track("b.txt");

		Thread.Sleep(50);
		WriteFile(scope $"{root}/a.txt", "a-changed");
		WriteFile(scope $"{root}/b.txt", "b-changed");

		let changes = scope List<String>();
		defer { for (let s in changes) delete s; }
		Test.Assert(cs.Poll(changes));
		Test.Assert(changes.Count == 2);
	}

	[Test]
	public static void Track_DuplicateIsNoOp()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		WriteFile(scope $"{root}/file.txt", "v1");
		let mount = scope FileSystemMount(root);
		let cs = MakeImmediateChangeSource(mount);

		cs.Track("file.txt");
		cs.Track("file.txt"); // duplicate

		Thread.Sleep(50);
		WriteFile(scope $"{root}/file.txt", "v2 changed");

		let changes = scope List<String>();
		defer { for (let s in changes) delete s; }
		cs.Poll(changes);
		Test.Assert(changes.Count == 1); // not 2
	}

	[Test]
	public static void Poll_RespectsMinInterval()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		WriteFile(scope $"{root}/file.txt", "v1");
		let mount = scope FileSystemMount(root);
		let cs = mount.ChangeSource as FileSystemChangeSource;
		cs.MinPollIntervalSeconds = 60; // effectively disable polling
		cs.Track("file.txt");

		Thread.Sleep(50);
		WriteFile(scope $"{root}/file.txt", "v2");

		let changes = scope List<String>();
		defer { for (let s in changes) delete s; }
		// Should return false because the min interval hasn't elapsed.
		Test.Assert(!cs.Poll(changes));
	}

	[Test]
	public static void ChangeSource_LazilyCreated()
	{
		let root = scope String(); CreateTempRoot(root);
		defer { Directory.DelTree(root); }

		let mount = scope FileSystemMount(root);
		let cs1 = mount.ChangeSource;
		let cs2 = mount.ChangeSource;
		Test.Assert(cs1 === cs2); // same instance both times
	}
}
