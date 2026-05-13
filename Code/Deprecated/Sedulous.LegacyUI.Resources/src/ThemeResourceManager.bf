namespace Sedulous.LegacyUI.Resources;

using System;
using System.IO;
using Sedulous.Resources;

/// Loads ThemeResource from theme XML files.
public class ThemeResourceManager : ResourceManager<ThemeResource>
{
	protected override Result<ThemeResource, ResourceLoadError> LoadFromContext(ResourceLoadContext ctx)
	{
		let xmlText = scope String();
		Try!(ReadAllText(ctx.Stream, xmlText));

		let theme = ThemeXmlParser.Parse(xmlText);
		if (theme == null)
			return .Err(.InvalidFormat);

		let resource = new ThemeResource();
		resource.Theme = theme;
		if (ctx.Locator.Length > 0)
			resource.Name.Set(ctx.Locator);
		resource.AddRef();
		return .Ok(resource);
	}

	public override void Unload(ThemeResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}
}
