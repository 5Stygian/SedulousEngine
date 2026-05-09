namespace Sedulous.Editor.App;

using System;
using System.Collections;
using Sedulous.Editor.Core;
using Sedulous.Resources;
using Sedulous.Images;
using Sedulous.Textures.Resources;
using Sedulous.Textures.Importer;
using Sedulous.Geometry.Tooling.Resources;

/// Imports image files (.png, .jpg, .tga, .bmp, .hdr) as TextureResource.
/// Supports 2D textures with preset selection (3D, Sprite, UI, Sky) and
/// cubemap import when 6 face images are detected.
class TextureAssetImporter : IAssetImporter
{
	public void GetSupportedExtensions(List<String> outExtensions)
	{
		outExtensions.Add(new .(".png"));
		outExtensions.Add(new .(".jpg"));
		outExtensions.Add(new .(".jpeg"));
		outExtensions.Add(new .(".tga"));
		outExtensions.Add(new .(".bmp"));
		outExtensions.Add(new .(".hdr"));
	}

	public Result<ImportPreview> CreatePreview(StringView sourcePath)
	{
		// Verify the file can be loaded
		if (ImageLoaderFactory.LoadImage(sourcePath) case .Ok(var image))
		{
			defer delete image;

			let preview = new ImportPreview();
			preview.SourcePath = new String(sourcePath);

			// Derive name from filename without extension
			let fileName = scope String();
			System.IO.Path.GetFileNameWithoutExtension(sourcePath, fileName);

			let item = new ImportPreviewItem();
			item.Name = new String(fileName);
			item.Extension = new String(".texture");
			item.TypeLabel = new String(scope $"Texture ({image.Width}x{image.Height})");
			item.InternalIndex = 0;
			preview.Items.Add(item);

			// Build import options with smart defaults
			let options = new TextureImportOptions();

			// Detect HDR -> default to equirectangular sky
			let ext = scope String();
			System.IO.Path.GetExtension(sourcePath, ext);
			ext.ToLower();
			if (ext == ".hdr")
				options.Preset = .EquirectangularSky;

			// Detect cubemap face files
			if (TextureImporter.DetectCubemapFaces(sourcePath, options.CubemapFacePaths) case .Ok)
			{
				options.CubemapDetected = true;
				options.Preset = .CubemapSky;

				// Update item label to indicate cubemap
				delete item.TypeLabel;
				item.TypeLabel = new String(scope $"Cubemap ({image.Width}x{image.Height} per face)");
			}

			preview.Options = options;

			return .Ok(preview);
		}

		return .Err;
	}

	public Result<void> Import(ImportPreview preview, StringView outputDir,
		ResourceRegistry registry, Sedulous.Serialization.ISerializerProvider serializer)
	{
		if (preview.Items.Count == 0 || !preview.Items[0].Selected)
			return .Ok;

		let options = (preview.Options as TextureImportOptions) ?? scope TextureImportOptions();

		TextureResource texRes = null;
		defer { if (texRes != null) delete texRes; }

		// Import based on preset
		switch (options.Preset)
		{
		case .CubemapSky:
			if (options.CubemapDetected)
			{
				StringView[6] facePaths = .();
				for (int i = 0; i < 6; i++)
					facePaths[i] = options.CubemapFacePaths[i];

				if (TextureImporter.ImportCubemap(facePaths) case .Ok(let res))
					texRes = res;
				else
					return .Err;
			}
			else
			{
				// Fallback to equirectangular if cubemap not detected
				if (TextureImporter.ImportEquirectangular(preview.SourcePath) case .Ok(let res))
					texRes = res;
				else
					return .Err;
			}

		case .EquirectangularSky:
			if (TextureImporter.ImportEquirectangular(preview.SourcePath) case .Ok(let res))
				texRes = res;
			else
				return .Err;

		case .Sprite:
			if (TextureImporter.Import2D(preview.SourcePath) case .Ok(let res))
			{
				res.SetupForSprite();
				texRes = res;
			}
			else
				return .Err;

		case .UI:
			if (TextureImporter.Import2D(preview.SourcePath) case .Ok(let res))
			{
				res.SetupForUI();
				texRes = res;
			}
			else
				return .Err;

		case .Texture3D:
			if (TextureImporter.Import2D(preview.SourcePath) case .Ok(let res))
				texRes = res;
			else
				return .Err;
		}

		// Use user-provided name from preview
		texRes.Name.Set(preview.Items[0].Name);

		// Ensure output directory exists
		if (!System.IO.Directory.Exists(outputDir))
			System.IO.Directory.CreateDirectory(outputDir);

		// Save to disk
		let fileName = scope String();
		fileName.AppendF("{}.texture", preview.Items[0].Name);
		ResourceSerializer.SanitizePath(fileName);

		let fullPath = scope String();
		System.IO.Path.InternalCombine(fullPath, outputDir, fileName);

		if (texRes.SaveToFile(fullPath, serializer) case .Err)
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

		registry.Register(texRes.Id, relPath);

		// Save registry
		let regFile = scope String();
		System.IO.Path.InternalCombine(regFile, registry.RootPath, scope $"{registry.Name}.registry");
		registry.SaveToFile(regFile);

		return .Ok;
	}
}
