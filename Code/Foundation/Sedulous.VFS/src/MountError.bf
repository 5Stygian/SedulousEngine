namespace Sedulous.VFS;

/// Failure modes for mount operations.
public enum MountError
{
	/// The locator does not exist in this mount.
	NotFound,

	/// Underlying I/O failed (read, write, or seek error).
	IOError,

	/// The mount refused access (read-only, permissions, etc.).
	AccessDenied,

	/// The operation is not supported by this mount (e.g. writing to a read-only mount).
	NotSupported
}
