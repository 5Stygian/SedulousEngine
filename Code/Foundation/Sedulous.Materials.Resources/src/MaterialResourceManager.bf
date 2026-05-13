using Sedulous.Resources;
using Sedulous.Serialization;
using System;
using System.IO;

namespace Sedulous.Materials.Resources;

class MaterialResourceManager : ResourceManager<MaterialResource>
{
	protected override Result<MaterialResource, ResourceLoadError> LoadFromContext(ResourceLoadContext ctx)
	{
		if (SerializerProvider == null)
			return .Err(.NotSupported);

		let text = scope String();
		Try!(ReadAllText(ctx.Stream, text));

		let reader = SerializerProvider.CreateReader(text);
		if (reader == null)
			return .Err(.InvalidFormat);
		defer delete reader;

		int32 version = 0;
		reader.Int32("version", ref version);
		if (version > MaterialResource.FileVersion)
			return .Err(.InvalidFormat);

		let resource = new MaterialResource();
		resource.Serialize(reader);
		resource.AddRef(); // Manager's ownership ref - released in Unload
		return .Ok(resource);
	}

	public override void Unload(MaterialResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	protected override Result<void, ResourceLoadError> ReloadResource(MaterialResource resource, ResourceLoadContext ctx)
	{
		if (SerializerProvider == null)
			return .Err(.NotSupported);

		let text = scope String();
		Try!(ReadAllText(ctx.Stream, text));

		let reader = SerializerProvider.CreateReader(text);
		if (reader == null)
			return .Err(.InvalidFormat);
		defer delete reader;

		int32 version = 0;
		reader.Int32("version", ref version);
		if (version > MaterialResource.FileVersion)
			return .Err(.InvalidFormat);

		return resource.Reload(reader);
	}
}
