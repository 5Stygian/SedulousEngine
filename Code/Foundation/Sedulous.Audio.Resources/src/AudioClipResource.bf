using System;
using System.IO;
using Sedulous.Audio;
using Sedulous.Resources;
using Sedulous.Serialization;

namespace Sedulous.Audio.Resources;

/// Resource wrapper for audio clips, enabling integration with the ResourceSystem.
/// Text metadata (sample rate, channels, format) is serialized via Serialize().
/// PCM data is stored as a binary sidecar file referenced by BinaryPath.
class AudioClipResource : Resource
{
	public const int32 FileVersion = 2;

	public override ResourceType ResourceType => .("audioclip");
	public override int32 SerializationVersion => FileVersion;

	private AudioClip mClip;

	/// Relative path to the binary sidecar file (PCM data).
	/// Set during save, read during load.
	public String BinaryPath = new .() ~ delete _;

	/// Audio metadata -- stored for deserialization (clip created by manager after loading sidecar).
	public int32 ClipSampleRate;
	public int32 ClipChannels;
	public int32 ClipFormat; // AudioFormat as int32

	/// Gets or sets the wrapped audio clip.
	public AudioClip Clip
	{
		get => mClip;
		set => mClip = value;
	}

	public ~this()
	{
		if (mClip != null)
			delete mClip;
	}

	protected override SerializationResult OnSerialize(Serializer s)
	{
		if (s.IsWriting && mClip != null)
		{
			ClipSampleRate = mClip.SampleRate;
			ClipChannels = mClip.Channels;
			ClipFormat = (int32)mClip.Format;
		}

		s.Int32("sampleRate", ref ClipSampleRate);
		s.Int32("channels", ref ClipChannels);
		s.Int32("format", ref ClipFormat);
		s.String("binaryPath", BinaryPath);

		return .Ok;
	}

	/// Saves text metadata via base class, then writes PCM data to binary sidecar.
	public override Result<void> SaveToFile(StringView path, Sedulous.Serialization.ISerializerProvider provider)
	{
		if (mClip == null || !mClip.IsLoaded)
			return .Err;

		// Set sidecar path (relative - just the filename with .bin appended)
		let writePath = scope String()..AppendF("{}.bin", path);
		BinaryPath.Clear();
		Path.GetFileName(writePath, BinaryPath);

		// Write text metadata via base class
		if (base.SaveToFile(path, provider) case .Err)
			return .Err;

		// Write binary sidecar (raw PCM data)
		let binStream = scope FileStream();
		if (binStream.Create(writePath, .Write) case .Err)
			return .Err;

		let pcmData = Span<uint8>(mClip.Data, mClip.DataLength);
		binStream.Write(pcmData);

		return .Ok;
	}
}
