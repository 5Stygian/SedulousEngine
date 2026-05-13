using System;

namespace Sedulous.Resources;

/// Listener for resource hot-reload events.
interface IResourceChangeListener
{
	/// Called after a resource has been reloaded in-place from its mount.
	/// `uri` is the scheme-prefixed URI the resource was loaded from.
	void OnResourceReloaded(StringView uri, Type resourceType, IResource resource);
}
