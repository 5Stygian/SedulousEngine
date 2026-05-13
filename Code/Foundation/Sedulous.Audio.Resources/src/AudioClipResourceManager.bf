using System;
using System.IO;
using System.Collections;
using Sedulous.Audio;
using Sedulous.Resources;
using Sedulous.Serialization;

namespace Sedulous.Audio.Resources;

/// Resource manager for AudioClip. Handles .audioclip files: text metadata
/// (sample rate, channels, format, sidecar path) plus a binary PCM sidecar.
///
/// Sidecar path inside the resource file is mount-relative (e.g.
/// "fx/explosion.audioclip.bin"), resolved by combining the locator's directory
/// with the recorded `BinaryPath` and opening it through `ctx.Mount`.
class AudioClipResourceManager : ResourceManager<AudioClipResource>
{
	private IAudioSystem mAudioSystem;

	public this(IAudioSystem audioSystem)
	{
		mAudioSystem = audioSystem;
	}

	protected override Result<AudioClipResource, ResourceLoadError> LoadFromContext(ResourceLoadContext ctx)
	{
		if (SerializerProvider == null)
			return .Err(.NotSupported);

		// Parse text metadata first.
		let text = scope String();
		Try!(ReadAllText(ctx.Stream, text));

		let reader = SerializerProvider.CreateReader(text);
		if (reader == null)
			return .Err(.InvalidFormat);
		defer delete reader;

		let resource = new AudioClipResource();
		if (resource.Serialize(reader) != .Ok)
		{
			delete resource;
			return .Err(.InvalidFormat);
		}

		// Resolve sidecar locator: same directory as the main file.
		if (resource.BinaryPath.IsEmpty || ctx.Mount == null)
		{
			delete resource;
			return .Err(.InvalidFormat);
		}

		let sidecarLocator = scope String();
		ResolveSiblingLocator(ctx.Locator, resource.BinaryPath, sidecarLocator);

		// Load PCM data from binary sidecar through the same mount.
		let sidecarResult = ctx.Mount.Open(sidecarLocator);
		if (sidecarResult case .Err)
		{
			delete resource;
			return .Err(.NotFound);
		}
		let binStream = sidecarResult.Value;
		defer delete binStream;

		// Read all PCM bytes.
		let binBytes = scope List<uint8>();
		if (ReadAllBytes(binStream, binBytes) case .Err)
		{
			delete resource;
			return .Err(.ReadError);
		}

		// Hand ownership of the PCM buffer to the clip.
		let pcm = new uint8[binBytes.Count]*;
		Internal.MemCpy(pcm, binBytes.Ptr, binBytes.Count);

		let clip = new AudioClip(
			pcm, binBytes.Count,
			resource.ClipSampleRate,
			resource.ClipChannels,
			(AudioFormat)resource.ClipFormat,
			true);
		resource.Clip = clip;

		resource.AddRef();
		return .Ok(resource);
	}

	public override void Unload(AudioClipResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	/// Combines the directory portion of `mainLocator` with `siblingName`. e.g.
	/// "fx/explosion.audioclip" + "explosion.audioclip.bin" -> "fx/explosion.audioclip.bin".
	private static void ResolveSiblingLocator(StringView mainLocator, StringView siblingName, String outLocator)
	{
		let slash = mainLocator.LastIndexOf('/');
		if (slash >= 0)
		{
			outLocator.Append(mainLocator.Substring(0, slash + 1));
		}
		outLocator.Append(siblingName);
	}
}
