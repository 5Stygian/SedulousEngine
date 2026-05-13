using System;
using Sedulous.Serialization;

namespace Sedulous.Resources;

/// Interface for resource managers that handle specific resource types.
///
/// Managers are byte-source-agnostic - they receive a `ResourceLoadContext`
/// that carries the primary stream plus optional mount/locator for resources
/// that need to open siblings (e.g. PCM sidecar of an audio clip).
interface IResourceManager
{
	/// Gets the type of resource this manager handles.
	Type ResourceType { get; }

	/// Serializer provider used by formats that delegate parsing through it.
	ISerializerProvider SerializerProvider { get; set; }

	/// Loads a resource. Caller owns `ctx.Stream` and remains responsible for
	/// closing/deleting it after `Load` returns.
	Result<ResourceHandle<IResource>, ResourceLoadError> Load(ResourceLoadContext ctx);

	/// Unloads a resource (releases the manager's ownership ref).
	void Unload(ref ResourceHandle<IResource> resource);

	/// Reloads an existing resource in-place from a fresh context. The
	/// resource's identity (and existing pointers) are preserved.
	Result<void, ResourceLoadError> Reload(IResource resource, ResourceLoadContext ctx);
}
