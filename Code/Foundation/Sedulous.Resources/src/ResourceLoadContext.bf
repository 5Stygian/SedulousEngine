using System;
using System.IO;
using Sedulous.VFS;

namespace Sedulous.Resources;

/// Context passed to `IResourceManager.Load` and `Reload`.
///
/// `Stream` is the primary input - the bytes of the resource being loaded. Most
/// managers only touch this field.
///
/// `Mount` and `Locator` are present so managers that need siblings of the main
/// file (e.g. audio clip with a `.bin` PCM sidecar) can open them through the
/// same mount the primary stream came from. They are `null` / empty for
/// synthetic loads where no mount is involved.
struct ResourceLoadContext
{
	public Stream Stream;
	public IMount Mount;
	public StringView Locator;

	public this(Stream stream, IMount mount, StringView locator)
	{
		Stream = stream;
		Mount = mount;
		Locator = locator;
	}

	/// Constructs a context with no mount - useful for synthetic loads
	/// (in-memory streams, tests).
	public this(Stream stream)
	{
		Stream = stream;
		Mount = null;
		Locator = default;
	}
}
