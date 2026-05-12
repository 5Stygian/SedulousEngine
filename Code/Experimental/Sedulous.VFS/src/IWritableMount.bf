using System;
using System.IO;

namespace Sedulous.VFS;

/// A mount that supports writes. Used by the editor for asset save / import flows.
///
/// Read-only mounts (paks, remote read-through caches, embedded resources) do not
/// implement this interface. Trying to write to them is a compile-time mismatch, not
/// a runtime `NotSupported`.
public interface IWritableMount : IMount
{
	/// Writes `data` to `locator`, creating it if missing and replacing it if present.
	/// Intermediate directories are created as needed. The stream is consumed but not
	/// owned by the mount - caller still deletes it.
	Result<void, MountError> Save(StringView locator, Stream data);

	/// Deletes the entry at `locator`. Returns `.Err(.NotFound)` if it doesn't exist.
	Result<void, MountError> Delete(StringView locator);
}
