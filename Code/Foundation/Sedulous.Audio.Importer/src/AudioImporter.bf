namespace Sedulous.Audio.Importer;

using System;
using System.IO;
using Sedulous.Audio;
using Sedulous.Audio.Decoders;
using Sedulous.Audio.Resources;

/// Imports audio files into AudioClipResource objects.
/// Uses AudioDecoderFactory for format detection and decoding.
class AudioImporter
{
	private AudioDecoderFactory mDecoderFactory;

	public this(AudioDecoderFactory decoderFactory)
	{
		mDecoderFactory = decoderFactory;
	}

	/// Imports an audio file as an AudioClipResource.
	/// Decodes the file to PCM and wraps it in a resource.
	public Result<AudioClipResource> Import(StringView path)
	{
		if (mDecoderFactory == null)
			return .Err;

		if (mDecoderFactory.DecodeFile(path) case .Ok(let clip))
		{
			let resource = new AudioClipResource();
			resource.Clip = clip;

			let name = scope String();
			Path.GetFileNameWithoutExtension(path, name);
			resource.Name.Set(name);
			resource.SourcePath.Set(path);

			return .Ok(resource);
		}

		return .Err;
	}

	/// Gets the list of supported file extensions from the decoder factory.
	public void GetSupportedExtensions(System.Collections.List<StringView> outExtensions)
	{
		if (mDecoderFactory != null)
			mDecoderFactory.GetSupportedExtensions(outExtensions);
	}

	/// Checks if the given file extension is supported.
	public bool SupportsExtension(StringView ext)
	{
		return mDecoderFactory?.SupportsExtension(ext) ?? false;
	}
}
