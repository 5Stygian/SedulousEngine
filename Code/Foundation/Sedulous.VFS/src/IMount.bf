using System;
using System.IO;

namespace Sedulous.VFS;

/// The bare minimum surface for a virtual filesystem: read bytes addressed by a locator.
///
/// A "mount" is a backing store - a folder on disk, a pak archive in memory, a remote
/// blob endpoint, etc. The locator is a mount-relative string ("folder/file.ext") with
/// forward-slash separators and no leading slash. The scheme prefix ("disk://", "pak://")
/// is the consumer's concern, not the mount's - mounts deal in their own locator space.
///
/// Capability splits live on top of this interface (`IEnumerableMount`, `IWatchableMount`,
/// `IWritableMount`). A mount only implements what it can actually do, so consumers do
/// `if (mount is IWritableMount)` rather than calling and getting `NotSupported` back.
public interface IMount
{
	/// Returns true if the locator names an existing entry in this mount.
	bool Exists(StringView locator);

	/// Opens the entry at `locator` for reading. Caller owns the returned stream and
	/// must `delete` it when done.
	Result<Stream, MountError> Open(StringView locator);
}
