using System;
using System.IO;
using Sedulous.Audio;
using Sedulous.Resources;
using Sedulous.Serialization;

namespace Sedulous.Audio.Resources;

/// Resource manager for loading and managing SoundCue resources.
class SoundCueResourceManager : ResourceManager<SoundCueResource>
{
	protected override Result<SoundCueResource, ResourceLoadError> LoadFromContext(ResourceLoadContext ctx)
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
		if (version > SoundCueResource.FileVersion)
			return .Err(.InvalidFormat);

		let resource = new SoundCueResource();
		resource.Serialize(reader);
		resource.AddRef();
		return .Ok(resource);
	}

	public override void Unload(SoundCueResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	protected override Result<void, ResourceLoadError> ReloadResource(SoundCueResource resource, ResourceLoadContext ctx)
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
		if (version > SoundCueResource.FileVersion)
			return .Err(.InvalidFormat);

		resource.Serialize(reader);
		return .Ok;
	}
}
