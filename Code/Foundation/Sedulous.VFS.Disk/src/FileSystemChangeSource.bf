using System;
using System.IO;
using System.Collections;
using System.Diagnostics;
using Sedulous.VFS;

namespace Sedulous.VFS.Disk;

/// Disk-backed change source - polls last-write timestamps for tracked locators.
///
/// Owned by the `FileSystemMount` that produced it. Resolves locators to absolute
/// paths via the owning mount's root.
class FileSystemChangeSource : IChangeSource
{
	private struct Entry : IDisposable
	{
		public String Locator;
		public DateTime LastModified;

		public void Dispose() mut
		{
			delete Locator;
			Locator = null;
		}
	}

	private FileSystemMount mMount;
	private List<Entry> mWatched = new .() ~ {
		for (var e in _) e.Dispose();
		delete _;
	};
	private double mMinPollIntervalSeconds = 0.5;
	private Stopwatch mSincePoll = new .() ~ delete _;

	/// Minimum seconds between actual filesystem scans. Calls to `Poll` more often than
	/// this return `false` immediately without touching disk. Defaults to 0.5 seconds.
	public double MinPollIntervalSeconds
	{
		get => mMinPollIntervalSeconds;
		set => mMinPollIntervalSeconds = value;
	}

	public this(FileSystemMount mount)
	{
		mMount = mount;
		mSincePoll.Start();
	}

	public void Track(StringView locator)
	{
		for (let e in mWatched)
		{
			if (e.Locator == locator)
				return;
		}

		let absPath = scope String();
		mMount.[Friend]ResolveAbsolute(locator, absPath);

		DateTime mtime = default;
		if (File.GetLastWriteTimeUtc(absPath) case .Ok(let t))
			mtime = t;

		mWatched.Add(.() { Locator = new String(locator), LastModified = mtime });
	}

	public void Untrack(StringView locator)
	{
		for (int i = 0; i < mWatched.Count; i++)
		{
			if (mWatched[i].Locator == locator)
			{
				var e = mWatched[i];
				e.Dispose();
				mWatched.RemoveAtFast(i);
				return;
			}
		}
	}

	public bool Poll(List<String> outChangedLocators)
	{
		if (mSincePoll.Elapsed.TotalSeconds < mMinPollIntervalSeconds)
			return false;
		mSincePoll.Restart();

		bool any = false;
		let absPath = scope String();
		for (var e in ref mWatched)
		{
			absPath.Clear();
			mMount.[Friend]ResolveAbsolute(e.Locator, absPath);

			DateTime current;
			if (File.GetLastWriteTimeUtc(absPath) case .Ok(let t))
				current = t;
			else
				continue;

			if (current != e.LastModified)
			{
				e.LastModified = current;
				outChangedLocators.Add(new String(e.Locator));
				any = true;
			}
		}
		return any;
	}
}
