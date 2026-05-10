namespace Sedulous.Editor.App;

using System;
using System.IO;
using System.Collections;
using Sedulous.Editor.Core;
using Sedulous.Resources;
using Sedulous.Audio;
using Sedulous.Audio.Decoders;
using Sedulous.Audio.Resources;

/// Imports audio files (.wav, .ogg, .mp3, .flac) as AudioClipResource.
/// The source audio file is copied as-is to .audioclip -- AudioClipResourceManager
/// handles decoding on load.
class AudioAssetImporter : IAssetImporter
{
	private AudioDecoderFactory mDecoder;

	public this(AudioDecoderFactory decoder)
	{
		mDecoder = decoder;
	}

	public void GetSupportedExtensions(List<String> outExtensions)
	{
		outExtensions.Add(new .(".wav"));
		outExtensions.Add(new .(".ogg"));
		outExtensions.Add(new .(".mp3"));
		outExtensions.Add(new .(".flac"));
	}

	public Result<ImportPreview> CreatePreview(StringView sourcePath)
	{
		if (mDecoder == null) return .Err;

		// Decode to verify validity and get metadata
		if (mDecoder.DecodeFile(sourcePath) case .Ok(let clip))
		{
			defer delete clip;

			let preview = new ImportPreview();
			preview.SourcePath = new String(sourcePath);

			let fileName = scope String();
			Path.GetFileNameWithoutExtension(sourcePath, fileName);

			let durationStr = scope String();
			let duration = clip.Duration;
			if (duration >= 60)
				durationStr.AppendF("{0}:{1:00.0}", (int)(duration / 60), duration % 60);
			else
				durationStr.AppendF("{0:F1}s", duration);

			let item = new ImportPreviewItem();
			item.Name = new String(fileName);
			item.Extension = new String(".audioclip");
			item.TypeLabel = new String(scope $"Audio ({clip.SampleRate}Hz, {clip.Channels}ch, {durationStr})");
			item.InternalIndex = 0;
			preview.Items.Add(item);

			return .Ok(preview);
		}

		return .Err;
	}

	public Result<void> Import(ImportPreview preview, StringView outputDir,
		ResourceRegistry registry, Sedulous.Serialization.ISerializerProvider serializer)
	{
		if (preview.Items.Count == 0 || !preview.Items[0].Selected)
			return .Ok;

		if (mDecoder == null) return .Err;

		// Decode the audio file to PCM
		AudioClip clip;
		if (mDecoder.DecodeFile(preview.SourcePath) case .Ok(let c))
			clip = c;
		else
			return .Err;

		// Create resource with decoded PCM data
		let resource = new AudioClipResource();
		resource.Clip = clip;
		resource.Name.Set(preview.Items[0].Name);
		resource.SourcePath.Set(preview.SourcePath);
		defer delete resource;

		// Ensure output directory exists
		if (!Directory.Exists(outputDir))
			Directory.CreateDirectory(outputDir);

		// Save as text metadata + binary PCM sidecar
		let fileName = scope String();
		fileName.AppendF("{}.audioclip", preview.Items[0].Name);

		let fullPath = scope String();
		Path.InternalCombine(fullPath, outputDir, fileName);

		if (resource.SaveToFile(fullPath, serializer) case .Err)
			return .Err;

		// Register in registry
		let relPrefix = scope String();
		if (registry.RootPath.Length > 0 && StringView(outputDir).StartsWith(registry.RootPath))
		{
			let after = StringView(outputDir)[registry.RootPath.Length...];
			if (after.StartsWith('/') || after.StartsWith('\\'))
				relPrefix.Set(after[1...]);
			else
				relPrefix.Set(after);
			relPrefix.Replace('\\', '/');
		}

		let relPath = scope String();
		if (relPrefix.Length > 0)
			relPath.AppendF("{}/{}", relPrefix, fileName);
		else
			relPath.Set(fileName);

		registry.Register(resource.Id, relPath);

		let regFile = scope String();
		Path.InternalCombine(regFile, registry.RootPath, scope $"{registry.Name}.registry");
		registry.SaveToFile(regFile);

		return .Ok;
	}
}
