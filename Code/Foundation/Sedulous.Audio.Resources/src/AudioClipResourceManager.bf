using System;
using System.IO;
using System.Collections;
using Sedulous.Audio;
using Sedulous.Resources;
using Sedulous.Serialization;

namespace Sedulous.Audio.Resources;

/// Resource manager for loading audio clips through the ResourceSystem.
/// Handles .audioclip files (text metadata + binary PCM sidecar).
class AudioClipResourceManager : ResourceManager<AudioClipResource>
{
	private IAudioSystem mAudioSystem;

	public this(IAudioSystem audioSystem)
	{
		mAudioSystem = audioSystem;
	}

	protected override Result<AudioClipResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		if (LoadTextFormat(path) case .Ok(let resource))
		{
			resource.AddRef();
			return .Ok(resource);
		}

		return .Err(.ReadError);
	}

	protected override Result<AudioClipResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		return .Err(.NotSupported);
	}

	public override void Unload(AudioClipResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	protected override Result<void, ResourceLoadError> ReloadResource(AudioClipResource resource, StringView path)
	{
		if (LoadTextFormat(path) case .Ok(let reloaded))
		{
			if (resource.Clip != null)
				delete resource.Clip;
			resource.Clip = reloaded.Clip;
			reloaded.[Friend]mClip = null;
			resource.ClipSampleRate = reloaded.ClipSampleRate;
			resource.ClipChannels = reloaded.ClipChannels;
			resource.ClipFormat = reloaded.ClipFormat;
			delete reloaded;
			return .Ok;
		}

		return .Err(.ReadError);
	}

	// ==================== Text + sidecar format ====================

	private Result<AudioClipResource> LoadTextFormat(StringView path)
	{
		if (SerializerProvider == null)
			return .Err;

		let text = scope String();
		if (File.ReadAllText(path, text) case .Err)
			return .Err;

		let reader = SerializerProvider.CreateReader(text);
		if (reader == null)
			return .Err;
		defer delete reader;

		let resource = new AudioClipResource();
		if (resource.Serialize(reader) != .Ok)
		{
			delete resource;
			return .Err;
		}

		// Load PCM data from binary sidecar
		if (resource.BinaryPath.IsEmpty)
		{
			delete resource;
			return .Err;
		}

		let relativeDir = Path.GetDirectoryPath(path, .. scope .());
		let readPath = scope String();
		Path.InternalCombine(readPath, relativeDir, resource.BinaryPath);

		let binStream = scope FileStream();
		if (binStream.Open(readPath, .Read) case .Err)
		{
			delete resource;
			return .Err;
		}

		let binLen = (int)binStream.Length;
		let binData = new uint8[binLen]*;
		if (binStream.TryRead(Span<uint8>(binData, binLen)) case .Err)
		{
			delete binData;
			delete resource;
			return .Err;
		}

		let clip = new AudioClip(
			binData, binLen,
			resource.ClipSampleRate,
			resource.ClipChannels,
			(AudioFormat)resource.ClipFormat,
			true
		);
		resource.Clip = clip;

		return .Ok(resource);
	}
}
