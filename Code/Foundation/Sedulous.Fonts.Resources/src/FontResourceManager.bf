using System;
using System.IO;
using System.Collections;
using Sedulous.Fonts;
using Sedulous.Resources;

namespace Sedulous.Fonts.Resources;

/// Resource manager for fonts. Reads font bytes from the stream and hands them
/// to `FontLoaderFactory.LoadFontFromMemory`. Caching is handled by the
/// `ResourceSystem`'s `ResourceCache`, not by this manager.
public class FontResourceManager : ResourceManager<FontResource>
{
	private FontLoadOptions mDefaultOptions;

	public this(FontLoadOptions defaultOptions = .Default)
	{
		mDefaultOptions = defaultOptions;
	}

	/// Default load options. Format hint defaults to ".ttf"; override with a
	/// custom `LoadFromContext` if you need to dispatch on locator extension.
	public FontLoadOptions DefaultOptions
	{
		get => mDefaultOptions;
		set => mDefaultOptions = value;
	}

	protected override Result<FontResource, ResourceLoadError> LoadFromContext(ResourceLoadContext ctx)
	{
		let bytes = scope List<uint8>();
		Try!(ReadAllBytes(ctx.Stream, bytes));

		// Best-effort format hint from the locator extension. Default to .ttf.
		let formatHint = ExtractExtension(ctx.Locator, ".ttf");

		if (FontLoaderFactory.LoadFontFromMemory(.(bytes.Ptr, bytes.Count), formatHint, mDefaultOptions) case .Ok(let font))
		{
			if (FontLoaderFactory.CreateAtlas(font, mDefaultOptions) case .Ok(let atlas))
			{
				let resource = new FontResource(font, atlas, mDefaultOptions);
				resource.AddRef();
				return .Ok(resource);
			}
			delete (Object)font;
			return .Err(.InvalidFormat);
		}

		return .Err(.InvalidFormat);
	}

	public override void Unload(FontResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	/// Returns the last `.ext` portion of `locator`, or `fallback` if none.
	private static StringView ExtractExtension(StringView locator, StringView fallback)
	{
		let dot = locator.LastIndexOf('.');
		if (dot < 0) return fallback;
		return locator.Substring(dot);
	}
}
