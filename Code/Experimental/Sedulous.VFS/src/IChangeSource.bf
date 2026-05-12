using System;
using System.Collections;

namespace Sedulous.VFS;

/// Detects changes to entries in a mount and reports them as locators.
///
/// Returned by `IWatchableMount.ChangeSource`. The implementation is mount-specific:
/// disk polls mtimes, a remote might subscribe to push notifications, a hypothetical
/// hot-reloadable pak watches its source file. Polling cadence is the implementation's
/// concern - callers just call `Poll` whenever it suits them.
public interface IChangeSource
{
	/// Begins watching `locator` for changes. Subsequent `Poll` calls will report it
	/// if its contents are modified. Tracking the same locator twice is a no-op.
	void Track(StringView locator);

	/// Stops watching `locator`. No-op if not tracked.
	void Untrack(StringView locator);

	/// Reports locators that have changed since the previous call. Returns `true` if
	/// any were appended. The implementation may also enforce an internal minimum
	/// interval - callers can poll at frame rate without overloading the backend.
	/// Appended strings are newly allocated and owned by the caller.
	bool Poll(List<String> outChangedLocators);
}
