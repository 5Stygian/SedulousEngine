namespace Sedulous.Engine.Core.Resources;

using System;
using System.IO;
using System.Collections;
using Sedulous.Resources;
using Sedulous.Engine.Core;
using Sedulous.Serialization;

/// Resource manager for .prefab files.
/// Loads prefab metadata (exposed parameters) on first load.
/// Full entity instantiation happens at runtime via PrefabSerializer.Instantiate.
class PrefabResourceManager : ResourceManager<PrefabResource>
{
	private ComponentTypeRegistry mTypeRegistry;
	private ISerializerProvider mSerializerProvider;

	public this(ComponentTypeRegistry typeRegistry, ISerializerProvider serializerProvider)
	{
		mTypeRegistry = typeRegistry;
		mSerializerProvider = serializerProvider;
	}

	public ~this()
	{

	}

	protected override Result<PrefabResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		let bytes = scope List<uint8>();
		bytes.Count = (.)memory.Length;
		if (memory.TryRead(bytes) case .Err)
			return .Err(.ReadError);

		let text = scope String((char8*)bytes.Ptr, bytes.Count);
		//text.Append(Span<char8>((char8*)bytes.Ptr, bytes.Count));

		let reader = mSerializerProvider.CreateReader(text);
		if (reader == null)
			return .Err(.ReadError);
		defer delete reader;

		// Load resource header + exposed parameters (no scene needed)
		let resource = new PrefabResource();
		resource.TypeRegistry = mTypeRegistry;
		// Scene is null - LoadParametersOnly will be called by OnSerialize
		resource.Serialize(reader);
		resource.AddRef(); // Manager's ownership ref - released in Unload

		return .Ok(resource);
	}

	public override void Unload(PrefabResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	/// Loads prefab entities into a scene for editing (prefab editor).
	/// The scene should already have component managers injected.
	public Result<void> LoadPrefabIntoScene(PrefabResource resource, Scene scene)
	{
		if (resource == null)
			return .Err;

		let path = scope String();
		if (resource.SourcePath.Length > 0)
			path.Set(resource.SourcePath);
		else if (resource.Name.Length > 0)
			path.Set(resource.Name);

		if (path.Length == 0)
			return .Err;

		let text = scope String();
		if (File.ReadAllText(path, text) case .Err)
			return .Err;

		let reader = mSerializerProvider.CreateReader(text);
		if (reader == null)
			return .Err;
		defer delete reader;

		// Load into scene - set Scene so OnSerialize loads entities
		resource.Scene = scene;
		resource.TypeRegistry = mTypeRegistry;
		resource.Serialize(reader);
		resource.Scene = null;

		return .Ok;
	}

	/// Saves a prefab from a scene to a file.
	/// If the file already exists, reuses the existing resource GUID.
	/// Returns the resource GUID written.
	public Result<Guid> SavePrefabToFile(Scene scene, List<ExposedParameterDescriptor> parameters, StringView path)
	{
		let resource = scope PrefabResource();
		resource.Scene = scene;
		resource.TypeRegistry = mTypeRegistry;

		// If the file already exists, read its resource header to preserve the GUID.
		if (File.Exists(path))
		{
			let existingText = scope String();
			if (File.ReadAllText(path, existingText) case .Ok)
			{
				let reader = mSerializerProvider.CreateReader(existingText);
				if (reader != null)
				{
					let existingRes = scope PrefabResource();
					existingRes.Serialize(reader);
					if (existingRes.Id != .Empty)
						resource.Id = existingRes.Id;
					delete reader;
				}
			}
		}

		// Copy parameters
		for (let param in parameters)
		{
			let copy = new ExposedParameterDescriptor();
			copy.Name.Set(param.Name);
			copy.EntityId = param.EntityId;
			copy.ComponentTypeId.Set(param.ComponentTypeId);
			copy.PropertyName.Set(param.PropertyName);
			resource.ExposedParameters.Add(copy);
		}

		let name = scope String();
		System.IO.Path.GetFileNameWithoutExtension(path, name);
		resource.Name = name;
		resource.SourcePath = scope .(path);

		if (resource.SaveToFile(path, mSerializerProvider) case .Err)
			return .Err;

		return .Ok(resource.Id);
	}
}
