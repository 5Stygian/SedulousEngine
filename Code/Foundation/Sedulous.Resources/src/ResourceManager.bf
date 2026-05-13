using System;
using System.IO;
using System.Collections;
using Sedulous.Serialization;

namespace Sedulous.Resources;

/// Abstract base class for resource managers.
///
/// Subclasses implement `LoadFromContext` to parse a `ResourceLoadContext` into
/// a resource. Most subclasses only read `ctx.Stream`; the `ReadAllBytes`/
/// `ReadAllText` helpers handle the common slurp-the-whole-stream case. Managers
/// that need siblings (PCM sidecar, etc.) use `ctx.Mount.Open(siblingLocator)`.
abstract class ResourceManager<T> : IResourceManager where T : IResource
{
	/// Serializer provider used by formats that delegate parsing through it.
	/// Set by the subsystem that creates this manager, or pulled from ResourceSystem.
	public ISerializerProvider SerializerProvider { get; set; }

	public Type ResourceType => typeof(T);

	public Result<ResourceHandle<IResource>, ResourceLoadError> Load(ResourceLoadContext ctx)
	{
		let handle = LoadFromContext(ctx);
		if (handle case .Err(let error))
			return .Err(error);
		return ResourceHandle<IResource>(handle.Value);
	}

	/// Parses a context into a resource. Most managers only use `ctx.Stream`.
	protected abstract Result<T, ResourceLoadError> LoadFromContext(ResourceLoadContext ctx);

	/// Override to implement resource unloading.
	public abstract void Unload(T resource);

	public void Unload(ref ResourceHandle<IResource> resource)
	{
		if (resource.Resource != null)
			Unload((T)resource.Resource);
	}

	public Result<void, ResourceLoadError> Reload(IResource resource, ResourceLoadContext ctx)
	{
		return ReloadResource((T)resource, ctx);
	}

	/// Override to implement in-place reload from a fresh context. Default
	/// returns `.NotSupported` - hot reload won't fire for this resource type.
	protected virtual Result<void, ResourceLoadError> ReloadResource(T resource, ResourceLoadContext ctx)
	{
		return .Err(.NotSupported);
	}

	// ==================== Stream helpers ====================

	/// Reads the remainder of `stream` into `outBytes`. Sizes `outBytes` to the
	/// stream's `Length` when known; otherwise reads in chunks until EOF.
	protected static Result<void, ResourceLoadError> ReadAllBytes(Stream stream, List<uint8> outBytes)
	{
		if (stream.Length > 0)
		{
			let len = (int)stream.Length;
			outBytes.Count = len;
			switch (stream.TryRead(.(outBytes.Ptr, len)))
			{
			case .Ok(let n):
				if (n != len) return .Err(.ReadError);
				return .Ok;
			case .Err:
				return .Err(.ReadError);
			}
		}

		uint8[4096] chunk = ?;
		while (true)
		{
			switch (stream.TryRead(.(&chunk[0], 4096)))
			{
			case .Ok(let n):
				if (n == 0) return .Ok;
				for (int i = 0; i < n; i++)
					outBytes.Add(chunk[i]);
			case .Err:
				return .Err(.ReadError);
			}
		}
	}

	/// Reads the remainder of `stream` and decodes the bytes as UTF-8 into `outText`.
	protected static Result<void, ResourceLoadError> ReadAllText(Stream stream, String outText)
	{
		let bytes = scope List<uint8>();
		Try!(ReadAllBytes(stream, bytes));
		if (bytes.Count > 0)
			outText.Append((char8*)bytes.Ptr, bytes.Count);
		return .Ok;
	}
}
