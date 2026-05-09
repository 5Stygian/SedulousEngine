namespace Sedulous.Textures.Importer;

using System;
using System.IO;
using System.Collections;
using Sedulous.Images;
using Sedulous.Textures;
using Sedulous.Textures.Resources;

/// Imports image files into TextureResource objects.
/// Handles 2D textures from single images and cubemaps from 6 face images.
class TextureImporter
{
	/// Imports a single image file as a 2D TextureResource.
	public static Result<TextureResource> Import2D(StringView path)
	{
		let image = Try!(ImageLoaderFactory.LoadImage(path));

		let resource = new TextureResource(image, true);
		resource.Shape = .Texture2D;

		let name = scope String();
		Path.GetFileNameWithoutExtension(path, name);
		resource.Name.Set(name);
		resource.SourcePath.Set(path);
		resource.SetupFor3D();

		return .Ok(resource);
	}

	/// Imports a single HDR image file as an equirectangular sky texture.
	public static Result<TextureResource> ImportEquirectangular(StringView path)
	{
		let image = Try!(ImageLoaderFactory.LoadImage(path));

		let resource = new TextureResource(image, true);
		let name = scope String();
		Path.GetFileNameWithoutExtension(path, name);
		resource.Name.Set(name);
		resource.SourcePath.Set(path);
		resource.SetupForEquirectangularSkybox();

		return .Ok(resource);
	}

	/// Imports 6 face images as a cubemap TextureResource.
	/// Face order: +X, -X, +Y, -Y, +Z, -Z.
	/// All faces must have the same dimensions and format.
	public static Result<TextureResource> ImportCubemap(StringView[6] facePaths)
	{
		Image[6] faces = .();
		defer { for (let face in faces) if (face != null) delete face; }

		// Load all 6 faces
		for (int i = 0; i < 6; i++)
		{
			if (ImageLoaderFactory.LoadImage(facePaths[i]) case .Ok(let image))
				faces[i] = image;
			else
				return .Err;
		}

		// Validate: all same dimensions and format, and square
		let w = faces[0].Width;
		let h = faces[0].Height;
		let fmt = faces[0].Format;

		if (w != h)
			return .Err; // Cubemap faces must be square

		for (int i = 1; i < 6; i++)
		{
			if (faces[i].Width != w || faces[i].Height != h || faces[i].Format != fmt)
				return .Err; // All faces must match
		}

		// Combine into a single image with 6 faces concatenated
		let faceSize = faces[0].Data.Length;
		let totalSize = faceSize * 6;
		let combinedData = new uint8[totalSize];

		for (int i = 0; i < 6; i++)
			Internal.MemCpy(&combinedData[i * faceSize], faces[i].Data.Ptr, faceSize);

		let combinedImage = new Image(w, h * 6, fmt, combinedData);
		delete combinedData;

		let resource = new TextureResource(combinedImage, true);
		resource.SetupForCubemapSkybox();

		// Derive name from the first face path
		let name = scope String();
		Path.GetFileNameWithoutExtension(facePaths[0], name);
		// Strip face suffix if present (e.g., "sky_px" -> "sky")
		for (let suffix in StringView[?]("_px", "_nx", "_py", "_ny", "_pz", "_nz",
			"_posx", "_negx", "_posy", "_negy", "_posz", "_negz",
			"_right", "_left", "_top", "_bottom", "_front", "_back"))
		{
			if (name.EndsWith(suffix, .OrdinalIgnoreCase))
			{
				name.RemoveFromEnd(suffix.Length);
				break;
			}
		}
		resource.Name.Set(name);

		return .Ok(resource);
	}

	/// Attempts to detect cubemap face files from a single path.
	/// Given "sky_px.png", looks for sky_nx.png, sky_py.png, etc.
	/// Returns the 6 face paths if all exist, or .Err if not a cubemap set.
	public static Result<void> DetectCubemapFaces(StringView path, String[6] outPaths)
	{
		let dir = scope String();
		Path.GetDirectoryPath(path, dir);

		let baseName = scope String();
		Path.GetFileNameWithoutExtension(path, baseName);

		let ext = scope String();
		Path.GetExtension(path, ext);

		// Try common face naming conventions (with and without prefix underscore)
		StringView[5][6] conventions = .(
			.("px", "nx", "py", "ny", "pz", "nz"),
			.("_px", "_nx", "_py", "_ny", "_pz", "_nz"),
			.("_posx", "_negx", "_posy", "_negy", "_posz", "_negz"),
			.("_right", "_left", "_top", "_bottom", "_front", "_back"),
			.("right", "left", "top", "bottom", "front", "back")
		);

		for (let convention in conventions)
		{
			// Check if baseName ends with any suffix in this convention
			int matchedFace = -1;
			for (int i = 0; i < 6; i++)
			{
				if (baseName.EndsWith(convention[i], .OrdinalIgnoreCase))
				{
					matchedFace = i;
					break;
				}
			}

			if (matchedFace < 0)
				continue;

			// Strip the matched suffix to get the prefix
			let prefix = scope String(baseName);
			prefix.RemoveFromEnd(convention[matchedFace].Length);

			// Check all 6 faces exist
			bool allExist = true;
			for (int i = 0; i < 6; i++)
			{
				outPaths[i].Clear();
				Path.InternalCombine(outPaths[i], dir, scope $"{prefix}{convention[i]}{ext}");

				if (!File.Exists(outPaths[i]))
				{
					allExist = false;
					break;
				}
			}

			if (allExist)
				return .Ok;
		}

		return .Err;
	}
}
