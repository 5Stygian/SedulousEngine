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
using Sedulous.Audio;
using Sedulous.Audio.Resources;
using Sedulous.Engine.Audio;

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

/// Creates editor pages for .audioclip files with playback preview.
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
		// Load clip resource
		AudioClipResource clipRes = null;
		if (context.ResourceSystem.LoadResource<AudioClipResource>(path) case .Ok(let handle))
			clipRes = handle.Resource;

		// Get audio system from the editor's own context (not RuntimeContext)
		IAudioSystem audioSystem = null;
		if (let audioSub = context.RuntimeContext?.GetSubsystem<AudioSubsystem>())
			audioSystem = audioSub.AudioSystem;

		let page = new AudioClipEditorPage(path, clipRes, audioSystem);
		page.SetContentView(BuildAudioClipView(clipRes, page));
		return page;
	}

	private static View BuildAudioClipView(AudioClipResource clipRes, AudioClipEditorPage page)
	{
		let root = new FlexLayout();
		root.Direction = .Vertical;
		root.Padding = .(16);
		root.Spacing = 12;

		// Title
		let name = scope String();
		System.IO.Path.GetFileNameWithoutExtension(page.FilePath, name);
		let titleLabel = new Label();
		titleLabel.SetText(scope $"Audio Clip: {name}");
		titleLabel.FontSize = 16;
		titleLabel.TextColor = .(220, 225, 235, 255);
		root.AddView(titleLabel, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(28)) });

		// Separator
		let sep = new Panel();
		sep.Background = new ColorDrawable(.(60, 65, 80, 255));
		root.AddView(sep, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(1)) });

		// Metadata
		if (clipRes?.Clip != null)
		{
			let clip = clipRes.Clip;

			AddInfoRow(root, "Sample Rate", scope $"{clip.SampleRate} Hz");
			AddInfoRow(root, "Channels", scope $"{clip.Channels} ({(clip.Channels == 1) ? "Mono" : "Stereo"})");
			AddInfoRow(root, "Format", scope $"{clip.Format}");
			AddInfoRow(root, "Duration", FormatDuration(clip.Duration, .. scope .()));
			AddInfoRow(root, "Frames", scope $"{clip.FrameCount}");

			let dataSize = clip.DataLength;
			if (dataSize > 1024 * 1024)
				AddInfoRow(root, "Data Size", scope $"{dataSize / (1024 * 1024)} MB");
			else
				AddInfoRow(root, "Data Size", scope $"{dataSize / 1024} KB");
		}
		else
		{
			let errorLabel = new Label();
			errorLabel.SetText("Failed to load audio clip");
			errorLabel.TextColor = .(220, 100, 100, 255);
			root.AddView(errorLabel, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(20)) });
		}

		// Separator
		let sep2 = new Panel();
		sep2.Background = new ColorDrawable(.(60, 65, 80, 255));
		root.AddView(sep2, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(1)) });

		// Playback controls
		let controls = new FlexLayout();
		controls.Direction = .Horizontal;
		controls.Spacing = 8;

		let playBtn = new Button("Play");
		playBtn.OnClick.Add(new [=page] (btn) => { page.Play(); });
		controls.AddView(playBtn, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(80)), Height = .Fixed(.Px(28)) });

		let pauseBtn = new Button("Pause");
		pauseBtn.OnClick.Add(new [=page] (btn) => { page.Pause(); });
		controls.AddView(pauseBtn, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(80)), Height = .Fixed(.Px(28)) });

		let stopBtn = new Button("Stop");
		stopBtn.OnClick.Add(new [=page] (btn) => { page.Stop(); });
		controls.AddView(stopBtn, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(80)), Height = .Fixed(.Px(28)) });

		root.AddView(controls, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(32)) });

		// Volume slider
		let volumeRow = new FlexLayout();
		volumeRow.Direction = .Horizontal;
		volumeRow.Spacing = 8;

		let volumeLabel = new Label();
		volumeLabel.SetText("Volume:");
		volumeLabel.TextColor = .(140, 140, 155, 255);
		volumeRow.AddView(volumeLabel, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(60)), Height = .Match });

		let volumeSlider = new Slider(0, 1, 1);
		volumeSlider.OnValueChanged.Add(new [=page] (s, val) => {
			if (page.Source != null)
				page.Source.Volume = val;
		});
		volumeRow.AddView(volumeSlider, new FlexLayout.LayoutParams() { Grow = 1, Height = .Match });

		root.AddView(volumeRow, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(24)) });

		// Loop checkbox
		let loopCheck = new CheckBox("Loop", false);
		loopCheck.OnCheckedChanged.Add(new [=page] (cb, val) => {
			if (page.Source != null)
				page.Source.Loop = val;
		});
		root.AddView(loopCheck, new FlexLayout.LayoutParams() { Width = .Wrap, Height = .Fixed(.Px(24)) });

		return root;
	}

	public static void AddInfoRow(FlexLayout container, StringView name, StringView value)
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

	public static void FormatDuration(float seconds, String outStr)
	{
		if (seconds >= 60)
			outStr.AppendF("{0}:{1:00.1}", (int)(seconds / 60), seconds % 60);
		else
			outStr.AppendF("{0:F2}s", seconds);
	}
}

/// Creates editor pages for .soundcue files with preview playback.
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
		// Load cue resource
		SoundCueResource cueRes = null;
		if (context.ResourceSystem.LoadResource<SoundCueResource>(path) case .Ok(let handle))
			cueRes = handle.Resource;

		// Get audio system from the editor's own context
		IAudioSystem audioSystem = null;
		if (let audioSub = context.RuntimeContext?.GetSubsystem<AudioSubsystem>())
			audioSystem = audioSub.AudioSystem;

		let page = new ResourceEditorPage(path, "Sound Cue");

		let root = new FlexLayout();
		root.Direction = .Vertical;
		root.Padding = .(16);
		root.Spacing = 12;

		// Title
		let name = scope String();
		System.IO.Path.GetFileNameWithoutExtension(path, name);
		let titleLabel = new Label();
		titleLabel.SetText(scope $"Sound Cue: {name}");
		titleLabel.FontSize = 16;
		titleLabel.TextColor = .(220, 225, 235, 255);
		root.AddView(titleLabel, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(28)) });

		let sep = new Panel();
		sep.Background = new ColorDrawable(.(60, 65, 80, 255));
		root.AddView(sep, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(1)) });

		if (cueRes?.Cue != null)
		{
			let cue = cueRes.Cue;

			// Cue properties
			AudioClipEditorPageFactory.AddInfoRow(root, "Selection Mode", scope $"{cue.SelectionMode}");
			AudioClipEditorPageFactory.AddInfoRow(root, "Entries", scope $"{cue.Entries.Count}");
			AudioClipEditorPageFactory.AddInfoRow(root, "Max Instances", scope $"{cue.MaxInstances}");
			AudioClipEditorPageFactory.AddInfoRow(root, "Priority", scope $"{cue.Priority}");
			AudioClipEditorPageFactory.AddInfoRow(root, "Cooldown", scope $"{cue.Cooldown:F2}s");
			AudioClipEditorPageFactory.AddInfoRow(root, "Bus", cue.BusName);

			// Entry list
			if (cue.Entries.Count > 0)
			{
				let sep2 = new Panel();
				sep2.Background = new ColorDrawable(.(60, 65, 80, 255));
				root.AddView(sep2, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(1)) });

				let entriesLabel = new Label();
				entriesLabel.SetText("Entries");
				entriesLabel.FontSize = 13;
				entriesLabel.TextColor = .(180, 180, 195, 255);
				root.AddView(entriesLabel, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(22)) });

				for (int i = 0; i < cue.Entries.Count; i++)
				{
					let entry = cue.Entries[i];
					let clipRef = (i < cueRes.ClipRefs.Count) ? cueRes.ClipRefs[i] : ResourceRef();

					let entryLabel = scope String();
					entryLabel.AppendF("  [{0}] W:{1:F1} Vol:{2:F2}-{3:F2} Pitch:{4:F2}-{5:F2}",
						i, entry.Weight, entry.VolumeMin, entry.VolumeMax, entry.PitchMin, entry.PitchMax);

					if (clipRef.Path != null && clipRef.Path.Length > 0)
						entryLabel.AppendF(" -> {}", clipRef.Path);

					AudioClipEditorPageFactory.AddInfoRow(root, scope $"Entry {i}", entryLabel);
				}
			}

			// Play button (plays the cue via the audio system)
			let sep3 = new Panel();
			sep3.Background = new ColorDrawable(.(60, 65, 80, 255));
			root.AddView(sep3, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(1)) });

			if (audioSystem != null)
			{
				let playBtn = new Button("Play Cue");
				playBtn.OnClick.Add(new [=audioSystem, =cue] (btn) => {
					audioSystem.PlayCue(cue);
				});
				root.AddView(playBtn, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(100)), Height = .Fixed(.Px(28)) });
			}
		}
		else
		{
			let errorLabel = new Label();
			errorLabel.SetText("Failed to load sound cue");
			errorLabel.TextColor = .(220, 100, 100, 255);
			root.AddView(errorLabel, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(20)) });
		}

		page.SetContentView(root);
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
