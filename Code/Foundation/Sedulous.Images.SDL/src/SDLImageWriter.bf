using System;
using SDL3;

namespace Sedulous.Images.SDL;

/// SDL3_image-backed image writer. Supports PNG, JPG, and AVIF output.
class SDLImageWriter : IImageWriter
{
	private static Self sInstance = null;

	public static bool Initialized => sInstance != null;

	public static void Initialize()
	{
		if (sInstance == null)
		{
			sInstance = new .();
			ImageWriterFactory.RegisterWriter(sInstance);
		}
	}

	public bool SupportsFormat(ImageFileFormat format)
	{
		switch (format)
		{
		case .PNG, .JPG, .BMP: return true;
		}
	}

	public Result<void> Save(Image image, StringView path, ImageFileFormat format, int32 jpgQuality = 90)
	{
		if (image == null || image.Width == 0 || image.Height == 0)
			return .Err;

		// Determine SDL pixel format from image format
		SDL_PixelFormat sdlFormat;
		switch (image.Format)
		{
		case .RGBA8: sdlFormat = .SDL_PIXELFORMAT_RGBA32;
		case .BGRA8: sdlFormat = .SDL_PIXELFORMAT_BGRA32;
		case .RGB8:  sdlFormat = .SDL_PIXELFORMAT_RGB24;
		case .BGR8:  sdlFormat = .SDL_PIXELFORMAT_BGR24;
		default:
			// Unsupported format for direct surface creation
			return .Err;
		}

		let bpp = Image.GetBytesPerPixel(image.Format);
		let pitch = (int32)(image.Width * bpp);

		// Create SDL surface from image pixel data (no copy - surface borrows the pointer)
		let surface = SDL_CreateSurfaceFrom(
			(int32)image.Width, (int32)image.Height,
			sdlFormat, (void*)image.Data.Ptr, pitch);

		if (surface == null)
			return .Err;

		defer SDL_DestroySurface(surface);

		// Save using the appropriate SDL_image function
		let pathStr = path.ToScopeCStr!();
		bool ok = false;
		switch (format)
		{
		case .PNG: ok = SDL3_image.IMG_SavePNG(surface, pathStr);
		case .JPG: ok = SDL3_image.IMG_SaveJPG(surface, pathStr, jpgQuality);
		case .BMP: ok = SDL_SaveBMP(surface, pathStr);
		}

		return ok ? .Ok : .Err;
	}
}
