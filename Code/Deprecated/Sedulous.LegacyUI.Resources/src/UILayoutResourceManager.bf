namespace Sedulous.LegacyUI.Resources;

using System;
using System.IO;
using Sedulous.Resources;

/// Loads UILayoutResource from UI XML files. The resource owns the loaded XML
/// text - it's stored as-is and parsed lazily by consumers.
public class UILayoutResourceManager : ResourceManager<UILayoutResource>
{
	protected override Result<UILayoutResource, ResourceLoadError> LoadFromContext(ResourceLoadContext ctx)
	{
		let xmlText = new String();
		if (ReadAllText(ctx.Stream, xmlText) case .Err)
		{
			delete xmlText;
			return .Err(.ReadError);
		}

		let resource = new UILayoutResource();
		resource.XmlSource = xmlText;
		if (ctx.Locator.Length > 0)
			resource.Name.Set(ctx.Locator);
		resource.AddRef();
		return .Ok(resource);
	}

	public override void Unload(UILayoutResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}
}
