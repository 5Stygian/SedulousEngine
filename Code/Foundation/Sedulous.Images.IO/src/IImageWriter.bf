namespace Sedulous.Images;

using System;

/// Format for image file encoding.
public enum ImageFileFormat
{
	PNG,
	JPG,
	BMP
}

/// Interface for encoding and saving images to files.
/// Implementations may use SDL_image, stb_image_write, or other backends.
public interface IImageWriter
{
	/// Saves an image to a file in the specified format.
	/// For JPG, quality ranges from 0-100.
	Result<void> Save(Image image, StringView path, ImageFileFormat format, int32 jpgQuality = 90);

	/// Returns true if this writer supports the given format.
	bool SupportsFormat(ImageFileFormat format);
}
