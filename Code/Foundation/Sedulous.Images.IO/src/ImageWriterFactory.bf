using System;
using System.Collections;

namespace Sedulous.Images;

/// Factory for saving images via registered IImageWriter implementations.
/// Register writers at startup, call SaveImage with the desired format.
/// The factory selects the first writer that supports the requested format.
public static class ImageWriterFactory
{
	private static List<IImageWriter> sWriters = new .() ~ DeleteContainerAndItems!(_);

	/// Registers an image writer. Takes ownership.
	public static void RegisterWriter(IImageWriter writer)
	{
		sWriters.Add(writer);
	}

	/// Saves an image to a file using the first registered writer that
	/// supports the requested format.
	public static Result<void> SaveImage(Image image, StringView path, ImageFileFormat format = .PNG, int32 jpgQuality = 90)
	{
		for (let writer in sWriters)
		{
			if (writer.SupportsFormat(format))
				return writer.Save(image, path, format, jpgQuality);
		}
		return .Err;
	}
}
