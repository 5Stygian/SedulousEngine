namespace Sedulous.Editor.App;

using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.UI.Toolkit;
using Sedulous.Editor.Core;
using Sedulous.Images;
using Sedulous.Textures;
using Sedulous.Textures.Resources;
using Sedulous.Resources;

/// Creates editor pages for .texture files.
/// Displays image preview (FitCenter) and metadata properties.
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
		// Load the texture resource via resource system
		TextureResource texRes = null;
		if (context.ResourceSystem.LoadResource<TextureResource>(path) case .Ok(let handle))
			texRes = handle.Resource;

		let page = new TextureEditorPage(path, texRes);
		page.SetContentView(BuildTextureView(path, texRes, page));
		return page;
	}

	private static View BuildTextureView(StringView path, TextureResource texRes, TextureEditorPage page)
	{
		let root = new SplitView(.Horizontal);

		// Left: image preview with dark background
		let previewPanel = new Panel();
		previewPanel.Background = new ColorDrawable(.(30, 30, 35, 255));

		let imageView = new ImageView();
		imageView.ScaleType = .FitCenter;

		if (texRes?.Image != null)
		{
			let image = texRes.Image;
			let colorSpace = IsHdrFormat(image.Format) ? ImageColorSpace.Linear : ImageColorSpace.Srgb;
			let imageData = new ImageDataRef(image.Width, image.Height, image.Format,
				image.Data.Ptr, image.Data.Length, colorSpace);
			imageView.Image = imageData;
			page.SetImageDataRef(imageData);
		}

		previewPanel.AddView(imageView);

		// Right: metadata panel
		let infoPanel = new FlexLayout();
		infoPanel.Direction = .Vertical;
		infoPanel.Padding = .(8);
		infoPanel.Spacing = 4;

		AddInfoLabel(infoPanel, "Texture Properties", 14);
		AddSeparator(infoPanel);

		if (texRes != null)
		{
			let image = texRes.Image;
			if (image != null)
			{
				AddInfoRow(infoPanel, "Dimensions", scope $"{image.Width} x {image.Height}");
				AddInfoRow(infoPanel, "Format", scope $"{image.Format}");
				let dataSize = image.DataSize;
				if (dataSize > 1024 * 1024)
					AddInfoRow(infoPanel, "Data Size", scope $"{dataSize / (1024 * 1024)} MB");
				else
					AddInfoRow(infoPanel, "Data Size", scope $"{dataSize / 1024} KB");
			}

			AddInfoRow(infoPanel, "Shape", scope $"{texRes.Shape}");
			AddInfoRow(infoPanel, "Min Filter", scope $"{texRes.MinFilter}");
			AddInfoRow(infoPanel, "Mag Filter", scope $"{texRes.MagFilter}");
			AddInfoRow(infoPanel, "Wrap U", scope $"{texRes.WrapU}");
			AddInfoRow(infoPanel, "Wrap V", scope $"{texRes.WrapV}");
			AddInfoRow(infoPanel, "Mipmaps", texRes.GenerateMipmaps ? "Yes" : "No");
			AddInfoRow(infoPanel, "Anisotropy", scope $"{texRes.Anisotropy:F1}");
		}
		else
		{
			AddInfoLabel(infoPanel, "Failed to load texture", 12);
		}

		root.SetPanes(previewPanel, infoPanel);
		root.SplitRatio = 0.7f;

		return root;
	}

	private static void AddInfoLabel(FlexLayout container, StringView text, float fontSize)
	{
		let label = new Label();
		label.SetText(text);
		label.FontSize = fontSize;
		label.TextColor = .(180, 180, 195, 255);
		container.AddView(label, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(24)) });
	}

	private static void AddInfoRow(FlexLayout container, StringView name, StringView value)
	{
		let row = new FlexLayout();
		row.Direction = .Horizontal;

		let nameLabel = new Label();
		nameLabel.SetText(scope $"{name}:");
		nameLabel.TextColor = .(140, 140, 155, 255);
		row.AddView(nameLabel, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(100)), Height = .Match });

		let valueLabel = new Label();
		valueLabel.SetText(value);
		valueLabel.TextColor = .(220, 220, 230, 255);
		row.AddView(valueLabel, new FlexLayout.LayoutParams() { Grow = 1, Height = .Match });

		container.AddView(row, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(20)) });
	}

	private static void AddSeparator(FlexLayout container)
	{
		let sep = new Panel();
		sep.Background = new ColorDrawable(.(60, 65, 80, 255));
		container.AddView(sep, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(1)) });
	}

	private static bool IsHdrFormat(PixelFormat format)
	{
		switch (format)
		{
		case .R16F, .RG16F, .RGB16F, .RGBA16F,
			 .R32F, .RG32F, .RGB32F, .RGBA32F:
			return true;
		default:
			return false;
		}
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
