namespace Sedulous.VFS;

/// A mount whose contents may change at runtime and can report those changes.
///
/// The mount owns its `IChangeSource` - it's created lazily on first access and
/// destroyed with the mount. Mounts whose contents are immutable for the duration
/// of the process (read-only paks, embedded blobs) don't implement this interface.
public interface IWatchableMount : IMount
{
	/// The change source for this mount. The mount owns it - do not delete.
	IChangeSource ChangeSource { get; }
}
