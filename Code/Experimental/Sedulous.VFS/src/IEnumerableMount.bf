using System;
using System.Collections;

namespace Sedulous.VFS;

/// A mount that can list its contents. Required by asset browsers and registry-build
/// passes that need to walk the mount without prior knowledge of what's in it.
///
/// Mounts whose contents are not naturally enumerable (e.g. a remote keyed-by-id store)
/// simply don't implement this interface.
public interface IEnumerableMount : IMount
{
	/// Enumerates the entries directly under `folderLocator` (non-recursive).
	///
	/// `folderLocator` is `""` to enumerate the mount root, or `"folder/"` (note the
	/// trailing slash) to enumerate a subfolder. Appends newly-allocated `String`
	/// entries to `outEntries`; directory entries end with `/`. Caller owns the
	/// appended strings.
	void Enumerate(StringView folderLocator, List<String> outEntries);
}
