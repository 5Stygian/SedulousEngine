namespace Sedulous.Editor.Core;

using System;
using Sedulous.Resources;
using Sedulous.VFS;

/// Editor-side bundle for a registered scheme: the mount that serves bytes,
/// the index that maps GUIDs to URIs, the URI scheme they share, and an
/// optional locator where the index is persisted within the mount.
///
/// The asset browser's tree and content adapters drive off `List<MountEntry>`.
/// EditorApplication is responsible for creating entries for builtin/project
/// schemes and any user-mounted ones, and adding them to
/// `EditorContext.MountEntries`.
///
/// The entry does not own the mount or index - those have their own lifetimes
/// managed by the application. `MountEntry` is just a co-locating view.
class MountEntry
{
	/// URI scheme this entry is registered under (e.g. "builtin", "project").
	public String Scheme = new .() ~ delete _;

	/// Byte source for this scheme. Never null.
	public IMount Mount;

	/// GUID -> URI map for this scheme. May be null if the entry doesn't track identity.
	public IResourceIndex Index;

	/// Locator inside `Mount` where the index is persisted. Empty when the
	/// index is in-memory only.
	public String IndexLocator = new .() ~ delete _;

	/// When true, the entry can't be unmounted by the user (builtin / project).
	public bool IsLocked;

	public this(StringView scheme, IMount mount, IResourceIndex index, StringView indexLocator = "", bool isLocked = false)
	{
		Scheme.Set(scheme);
		Mount = mount;
		Index = index;
		IndexLocator.Set(indexLocator);
		IsLocked = isLocked;
	}
}
