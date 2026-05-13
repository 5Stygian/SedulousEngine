using System;
using System.IO;

namespace Sedulous.VFS.Pak;

/// A read/write stream over an in-memory byte buffer that the stream owns.
///
/// `PakMount.Open` reads (and decompresses) an entry into a freshly allocated buffer
/// and hands it to `PakEntryStream`. The buffer lives as long as the stream, so the
/// caller's `delete` on the stream also frees the bytes.
public class PakEntryStream : FixedMemoryStream
{
	private uint8[] mOwnedBuffer ~ delete _;

	public this(uint8[] buffer) : base(Span<uint8>(buffer))
	{
		mOwnedBuffer = buffer;
	}
}
