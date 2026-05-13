namespace Sedulous.Resources;

using System;
using System.IO;
using System.Collections;
using System.Threading;

/// In-memory `IResourceIndex` backed by dictionaries. Thread-safe via Monitor.
///
/// Persistence is stream-based - one `guid=uri` line per entry. The text
/// format is the same as the old on-disk registry layout so existing index
/// files round-trip, but the I/O is now a `Stream` so callers route writes
/// through whichever mount they choose.
class InMemoryResourceIndex : IResourceIndex
{
	private Monitor mMonitor = new .() ~ delete _;
	private Dictionary<Guid, String> mIdToUri = new .() ~ DeleteDictionaryAndValues!(_);
	private Dictionary<String, Guid> mUriToId = new .() ~ delete _; // Keys shared with mIdToUri values

	public int Count
	{
		get
		{
			using (mMonitor.Enter())
				return mIdToUri.Count;
		}
	}

	public void Register(Guid id, StringView uri)
	{
		using (mMonitor.Enter())
		{
			if (mIdToUri.TryGetValue(id, let existing))
			{
				mUriToId.Remove(existing);
				delete existing;
				mIdToUri.Remove(id);
			}

			let stored = new String(uri);
			stored.Replace('\\', '/');
			mIdToUri[id] = stored;
			mUriToId[stored] = id; // shares the same String instance
		}
	}

	public void Unregister(Guid id)
	{
		using (mMonitor.Enter())
		{
			if (mIdToUri.TryGetValue(id, let uri))
			{
				mUriToId.Remove(uri);
				delete uri;
				mIdToUri.Remove(id);
			}
		}
	}

	public bool TryResolveUri(Guid id, String outUri)
	{
		using (mMonitor.Enter())
		{
			if (mIdToUri.TryGetValue(id, let uri))
			{
				outUri.Set(uri);
				return true;
			}
			return false;
		}
	}

	public bool TryResolveId(StringView uri, out Guid id)
	{
		using (mMonitor.Enter())
		{
			for (let kv in mUriToId)
			{
				if (StringView(kv.key) == uri)
				{
					id = kv.value;
					return true;
				}
			}
			id = default;
			return false;
		}
	}

	public void GetEntries(List<(Guid id, StringView uri)> outEntries)
	{
		using (mMonitor.Enter())
		{
			for (let kv in mIdToUri)
				outEntries.Add((kv.key, kv.value));
		}
	}

	public Result<void> SerializeTo(Stream stream)
	{
		using (mMonitor.Enter())
		{
			for (let kv in mIdToUri)
			{
				let line = scope String();
				kv.key.ToString(line);
				line.Append('=');
				line.Append(kv.value);
				line.Append('\n');
				if (stream.TryWrite(.((uint8*)line.Ptr, line.Length)) case .Err)
					return .Err;
			}
		}
		return .Ok;
	}

	public Result<void> DeserializeFrom(Stream stream)
	{
		// Read whole stream into a buffer, parse line by line.
		let bytes = scope List<uint8>();
		uint8[1024] buf = ?;
		while (true)
		{
			switch (stream.TryRead(.(&buf[0], 1024)))
			{
			case .Ok(let n):
				if (n == 0) break;
				for (int i = 0; i < n; i++)
					bytes.Add(buf[i]);
				continue;
			case .Err:
				return .Err;
			}
			break;
		}

		let text = StringView((char8*)bytes.Ptr, bytes.Count);
		int lineStart = 0;
		for (int i = 0; i <= text.Length; i++)
		{
			let atEnd = (i == text.Length);
			if (atEnd || text[i] == '\n')
			{
				var line = text.Substring(lineStart, i - lineStart);
				if (line.EndsWith('\r'))
					line = line.Substring(0, line.Length - 1);
				lineStart = i + 1;

				if (line.IsEmpty) continue;

				let eq = line.IndexOf('=');
				if (eq <= 0) continue;

				let guidStr = line.Substring(0, eq);
				let uri = line.Substring(eq + 1);

				if (Guid.Parse(guidStr) case .Ok(let id))
					Register(id, uri);
			}
		}
		return .Ok;
	}
}
