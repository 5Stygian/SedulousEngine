namespace Sedulous.Editor.App;

using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.Editor.Core;

/// Creates editor pages for .texture files.
class TextureEditorPageFactory : IEditorPageFactory
{
	public void GetSupportedExtensions(List<String> outExtensions)
	{
		outExtensions.Add(new .(".texture"));
	}

	public bool CanOpen(StringView path) =>
		path.EndsWith(".texture", .OrdinalIgnoreCase);

	public IEditorPage CreatePage(StringView path, EditorContext context)
	{
		let page = new ResourceEditorPage(path, "Texture");
		page.SetContentView(BuildPlaceholder("Texture", path));
		return page;
	}

	public static View BuildPlaceholder(StringView resourceType, StringView path)
	{
		let container = new FlexLayout();
		container.Direction = .Vertical;
		container.Padding = .(16);

		let name = scope String();
		System.IO.Path.GetFileNameWithoutExtension(path, name);

		let titleLabel = new Label();
		titleLabel.SetText(scope $"{resourceType}: {name}");
		titleLabel.FontSize = 16;
		titleLabel.HAlign = .Center;
		titleLabel.VAlign = .Middle;
		container.AddView(titleLabel, new FlexLayout.LayoutParams() { Width = .Match, Grow = 1 });

		return container;
	}
}

/// Creates editor pages for .material files.
class MaterialEditorPageFactory : IEditorPageFactory
{
	public void GetSupportedExtensions(List<String> outExtensions)
	{
		outExtensions.Add(new .(".material"));
	}

	public bool CanOpen(StringView path) =>
		path.EndsWith(".material", .OrdinalIgnoreCase);

	public IEditorPage CreatePage(StringView path, EditorContext context)
	{
		let page = new ResourceEditorPage(path, "Material");
		page.SetContentView(TextureEditorPageFactory.BuildPlaceholder("Material", path));
		return page;
	}
}

/// Creates editor pages for .mesh files.
class MeshEditorPageFactory : IEditorPageFactory
{
	public void GetSupportedExtensions(List<String> outExtensions)
	{
		outExtensions.Add(new .(".mesh"));
	}

	public bool CanOpen(StringView path) =>
		path.EndsWith(".mesh", .OrdinalIgnoreCase);

	public IEditorPage CreatePage(StringView path, EditorContext context)
	{
		let page = new ResourceEditorPage(path, "Mesh");
		page.SetContentView(TextureEditorPageFactory.BuildPlaceholder("Mesh", path));
		return page;
	}
}

/// Creates editor pages for .animation files.
class AnimationEditorPageFactory : IEditorPageFactory
{
	public void GetSupportedExtensions(List<String> outExtensions)
	{
		outExtensions.Add(new .(".animation"));
	}

	public bool CanOpen(StringView path) =>
		path.EndsWith(".animation", .OrdinalIgnoreCase);

	public IEditorPage CreatePage(StringView path, EditorContext context)
	{
		let page = new ResourceEditorPage(path, "Animation");
		page.SetContentView(TextureEditorPageFactory.BuildPlaceholder("Animation", path));
		return page;
	}
}

/// Creates editor pages for .skeleton files.
class SkeletonEditorPageFactory : IEditorPageFactory
{
	public void GetSupportedExtensions(List<String> outExtensions)
	{
		outExtensions.Add(new .(".skeleton"));
	}

	public bool CanOpen(StringView path) =>
		path.EndsWith(".skeleton", .OrdinalIgnoreCase);

	public IEditorPage CreatePage(StringView path, EditorContext context)
	{
		let page = new ResourceEditorPage(path, "Skeleton");
		page.SetContentView(TextureEditorPageFactory.BuildPlaceholder("Skeleton", path));
		return page;
	}
}

/// Creates editor pages for .animgraph files.
class AnimGraphEditorPageFactory : IEditorPageFactory
{
	public void GetSupportedExtensions(List<String> outExtensions)
	{
		outExtensions.Add(new .(".animgraph"));
	}

	public bool CanOpen(StringView path) =>
		path.EndsWith(".animgraph", .OrdinalIgnoreCase);

	public IEditorPage CreatePage(StringView path, EditorContext context)
	{
		let page = new ResourceEditorPage(path, "Animation Graph");
		page.SetContentView(TextureEditorPageFactory.BuildPlaceholder("Animation Graph", path));
		return page;
	}
}

/// Creates editor pages for .audioclip files.
class AudioClipEditorPageFactory : IEditorPageFactory
{
	public void GetSupportedExtensions(List<String> outExtensions)
	{
		outExtensions.Add(new .(".audioclip"));
	}

	public bool CanOpen(StringView path) =>
		path.EndsWith(".audioclip", .OrdinalIgnoreCase);

	public IEditorPage CreatePage(StringView path, EditorContext context)
	{
		let page = new ResourceEditorPage(path, "Audio Clip");
		page.SetContentView(TextureEditorPageFactory.BuildPlaceholder("Audio Clip", path));
		return page;
	}
}

/// Creates editor pages for .soundcue files.
class SoundCueEditorPageFactory : IEditorPageFactory
{
	public void GetSupportedExtensions(List<String> outExtensions)
	{
		outExtensions.Add(new .(".soundcue"));
	}

	public bool CanOpen(StringView path) =>
		path.EndsWith(".soundcue", .OrdinalIgnoreCase);

	public IEditorPage CreatePage(StringView path, EditorContext context)
	{
		let page = new ResourceEditorPage(path, "Sound Cue");
		page.SetContentView(TextureEditorPageFactory.BuildPlaceholder("Sound Cue", path));
		return page;
	}
}

/// Creates editor pages for .propanim files.
class PropAnimEditorPageFactory : IEditorPageFactory
{
	public void GetSupportedExtensions(List<String> outExtensions)
	{
		outExtensions.Add(new .(".propanim"));
	}

	public bool CanOpen(StringView path) =>
		path.EndsWith(".propanim", .OrdinalIgnoreCase);

	public IEditorPage CreatePage(StringView path, EditorContext context)
	{
		let page = new ResourceEditorPage(path, "Property Animation");
		page.SetContentView(TextureEditorPageFactory.BuildPlaceholder("Property Animation", path));
		return page;
	}
}

/// Creates editor pages for .particle files.
class ParticleEditorPageFactory : IEditorPageFactory
{
	public void GetSupportedExtensions(List<String> outExtensions)
	{
		outExtensions.Add(new .(".particle"));
	}

	public bool CanOpen(StringView path) =>
		path.EndsWith(".particle", .OrdinalIgnoreCase);

	public IEditorPage CreatePage(StringView path, EditorContext context)
	{
		let page = new ResourceEditorPage(path, "Particle Effect");
		page.SetContentView(TextureEditorPageFactory.BuildPlaceholder("Particle Effect", path));
		return page;
	}
}
