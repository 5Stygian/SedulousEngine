namespace UI2Sandbox;

using System;
using Sedulous.Runtime;
using Sedulous.Runtime.Client;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell.Input;
using Sedulous.UI2;
using Sedulous.UI2.Runtime;
using Sedulous.Images;

/// Minimal UI2 sandbox application. Extends Application directly (no engine).
/// App owns UIContext and RootView. Subsystem owns rendering pipeline.
class UI2SandboxApp : Application
{
	// Subsystem (registered with Context, cleaned up by Context)
	private UI2Subsystem mUI;

	// App-owned UI state (cleaned up in OnShutdown)
	private UIContext mUIContext;
	private RootView mRoot;
	private int32 mThemeIndex = 0; // 0=Dark, 1=Light, 2=RoundedDark
	private OwnedImageData mTestImage ~ delete _;
	private RepeatButton mRepeatBtn;
	private int32 mRepeatCount;

	protected override void OnInitialize(Context context)
	{
		// Create app-owned UI state
		mUIContext = new UIContext();
		mRoot = new RootView();

		// Set default theme
		ApplyTheme();

		// Create and register subsystem
		mUI = new UI2Subsystem();
		context.RegisterSubsystem<UI2Subsystem>(mUI);

		// Initialize rendering — pass app-owned context and root
		let shaderPath = scope String();
		GetAssetPath("shaders", shaderPath);

		if (mUI.InitializeRendering(
			mUIContext, mRoot,
			Device, SwapChain.Format, (int32)SwapChain.BufferCount,
			scope StringView[](shaderPath), Shell, Window) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize UI2 rendering");
			return;
		}

		// Load fonts
		let fontPath = scope String();
		GetAssetPath("fonts/roboto/Roboto-Regular.ttf", fontPath);
		mUI.LoadFont("Roboto", fontPath, .() { PixelHeight = 16 });
		mUI.LoadFont("Roboto", fontPath, .() { PixelHeight = 24 });

		// Generate a test image for ImageView demo
		mTestImage = GenerateCheckerboard(64, 64, 8, .(100, 140, 200, 255), .(40, 50, 70, 255));

		// Build initial UI
		BuildUI();

		Console.WriteLine("=== UI2 Sandbox Ready ===");
	}

	private void BuildUI()
	{
		// Main vertical layout filling the window
		let main = new FlexLayout() { Direction = .Vertical };
		mRoot.AddView(main);

		// TabView as the main navigation
		let tabView = new TabView() { TabsClosable = false };
		tabView.OnTabCloseRequested.Add(new (tv, idx) => { tv.RemoveTab(idx); });
		main.AddView(tabView, new FlexLayout.LayoutParams() { Grow = 1 });

		// === Tab 1: Controls ===
		let body = new FlexLayout() { Direction = .Horizontal, Spacing = 4 };
		tabView.AddTab("Controls", body);

		// Left panel — Controls demo
		let leftPanel = new FlexLayout() { Direction = .Vertical, Spacing = 8 };
		leftPanel.Padding = .(12, 8);
		body.AddView(leftPanel, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(300)) });

		// Buttons
		let btnRow = new FlexLayout() { Direction = .Horizontal, Spacing = 6 };
		btnRow.AddView(new Button("Click Me"));
		btnRow.AddView(new Button("Disabled") { IsEnabled = false });
		btnRow.AddView(new ToggleButton("Toggle"));
		leftPanel.AddView(btnRow);

		// RepeatButton
		let repeatRow = new FlexLayout() { Direction = .Horizontal, Spacing = 6 };
		let repeatLabel = new Label("Count: 0");
		let repeatBtn = new RepeatButton("Hold Me");
		mRepeatBtn = repeatBtn;
		repeatBtn.OnClick.Add(new (btn) =>
		{
			mRepeatCount++;
			repeatLabel.SetText(scope String()..AppendF("Count: {}", mRepeatCount));
		});
		repeatRow.AddView(repeatBtn);
		repeatRow.AddView(repeatLabel);
		leftPanel.AddView(repeatRow);

		// Spacer
		leftPanel.AddView(new Spacer(0, 4));

		// Toggle controls
		leftPanel.AddView(new CheckBox("Enable sounds", true));
		leftPanel.AddView(new CheckBox("Fullscreen"));
		leftPanel.AddView(new ToggleSwitch("VSync"));

		// Separator
		leftPanel.AddView(new Separator());

		// Radio group
		let radioGroup = new RadioGroup();
		radioGroup.AddRadioButton(new RadioButton("Low"));
		radioGroup.AddRadioButton(new RadioButton("Medium"));
		radioGroup.AddRadioButton(new RadioButton("High"));
		radioGroup.CheckAt(1);
		leftPanel.AddView(radioGroup);

		// Separator
		leftPanel.AddView(new Separator());

		// Slider
		leftPanel.AddView(new Label("Volume"));
		leftPanel.AddView(new Slider(0, 100, 75));

		// Progress bar
		leftPanel.AddView(new Label("Loading..."));
		leftPanel.AddView(new ProgressBar() { Value = 0.65f });

		// Center panel — Panel with Expanders
		let centerPanel = new FlexLayout() { Direction = .Vertical, Spacing = 8 };
		centerPanel.Padding = .(8);
		body.AddView(centerPanel, new FlexLayout.LayoutParams() { Grow = 1 });

		// Themed panel containing expanders
		let settingsPanel = new Panel();
		settingsPanel.Padding = .(8);
		settingsPanel.StyleId = new String("panel");
		let settingsLayout = new FlexLayout() { Direction = .Vertical, Spacing = 4 };
		settingsPanel.AddView(settingsLayout);
		centerPanel.AddView(settingsPanel);

		let expander1 = new Expander("Graphics Settings");
		let expanderContent1 = new FlexLayout() { Direction = .Vertical, Spacing = 4 };
		expanderContent1.AddView(new CheckBox("Anti-Aliasing"));
		expanderContent1.AddView(new CheckBox("Shadows", true));
		expanderContent1.AddView(new CheckBox("Bloom", true));
		expander1.SetContent(expanderContent1);
		settingsLayout.AddView(expander1);

		let expander2 = new Expander("Audio Settings");
		let expanderContent2 = new FlexLayout() { Direction = .Vertical, Spacing = 4 };
		expanderContent2.AddView(new Label("Master Volume"));
		expanderContent2.AddView(new Slider(0, 100, 80));
		expanderContent2.AddView(new Label("Music Volume"));
		expanderContent2.AddView(new Slider(0, 100, 50));
		expander2.SetContent(expanderContent2);
		settingsLayout.AddView(expander2);

		// Right panel — ImageView modes + Color swatches
		let rightPanel = new FlexLayout() { Direction = .Vertical, Spacing = 4 };
		rightPanel.Padding = .(4);
		body.AddView(rightPanel, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(200)) });

		// ImageView demos — all ScaleType modes
		rightPanel.AddView(new Label("None") { VAlign = .Top });
		let imgNone = new ImageView(mTestImage);
		imgNone.ScaleType = .None;
		imgNone.ClipsContent = true;
		rightPanel.AddView(imgNone, new FlexLayout.LayoutParams() { Height = .Fixed(.Px(48)) });

		rightPanel.AddView(new Label("FitCenter") { VAlign = .Top });
		let imgFit = new ImageView(mTestImage);
		imgFit.ScaleType = .FitCenter;
		rightPanel.AddView(imgFit, new FlexLayout.LayoutParams() { Height = .Fixed(.Px(48)) });

		rightPanel.AddView(new Label("FillBounds") { VAlign = .Top });
		let imgFill = new ImageView(mTestImage);
		imgFill.ScaleType = .FillBounds;
		rightPanel.AddView(imgFill, new FlexLayout.LayoutParams() { Height = .Fixed(.Px(48)) });

		rightPanel.AddView(new Label("CenterCrop") { VAlign = .Top });
		let imgCrop = new ImageView(mTestImage);
		imgCrop.ScaleType = .CenterCrop;
		rightPanel.AddView(imgCrop, new FlexLayout.LayoutParams() { Height = .Fixed(.Px(48)) });

		// Tinted image
		rightPanel.AddView(new Label("Tinted") { VAlign = .Top });
		let imgTint = new ImageView(mTestImage);
		imgTint.ScaleType = .FitCenter;
		imgTint.Tint = .(255, 100, 100, 255);
		rightPanel.AddView(imgTint, new FlexLayout.LayoutParams() { Height = .Fixed(.Px(48)) });

		rightPanel.AddView(new Separator());

		// Color swatches
		rightPanel.AddView(new Label("ColorView") { VAlign = .Top });
		let swatchFlow = new FlowLayout() { Orientation = .Horizontal, HSpacing = 4, VSpacing = 4 };
		rightPanel.AddView(swatchFlow);

		Color[?] swatchColors = .(
			.(220, 60, 60, 255), .(60, 180, 60, 255), .(60, 60, 220, 255),
			.(220, 180, 40, 255), .(180, 60, 180, 255), .(60, 180, 180, 255),
			.(220, 120, 60, 255), .(120, 60, 220, 255)
		);
		for (int i = 0; i < swatchColors.Count; i++)
		{
			let swatch = new ColorView(swatchColors[i], 40, 40);
			swatchFlow.AddView(swatch);
		}

		// === Tab 2: ScrollView demo ===
		let scrollDemo = new FlexLayout() { Direction = .Horizontal, Spacing = 8 };
		scrollDemo.Padding = .(12, 8);
		tabView.AddTab("ScrollView", scrollDemo);

		// Overlay mode (default)
		let overlayCol = new FlexLayout() { Direction = .Vertical, Spacing = 4 };
		overlayCol.AddView(new Label("Overlay Mode") { VAlign = .Top });
		let scrollOverlay = new ScrollView();
		scrollOverlay.ScrollBarMode = .Overlay;
		let overlayContent = new FlexLayout() { Direction = .Vertical, Spacing = 4 };
		for (int i = 0; i < 30; i++)
			overlayContent.AddView(new Label(scope String()..AppendF("Overlay item {}", i + 1)));
		scrollOverlay.AddView(overlayContent);
		overlayCol.AddView(scrollOverlay, new FlexLayout.LayoutParams() { Grow = 1 });
		scrollDemo.AddView(overlayCol, new FlexLayout.LayoutParams() { Grow = 1 });

		// Reserved mode
		let reservedCol = new FlexLayout() { Direction = .Vertical, Spacing = 4 };
		reservedCol.AddView(new Label("Reserved Mode") { VAlign = .Top });
		let scrollReserved = new ScrollView();
		scrollReserved.ScrollBarMode = .Reserved;
		let reservedContent = new FlexLayout() { Direction = .Vertical, Spacing = 4 };
		for (int i = 0; i < 30; i++)
			reservedContent.AddView(new Label(scope String()..AppendF("Reserved item {}", i + 1)));
		scrollReserved.AddView(reservedContent);
		reservedCol.AddView(scrollReserved, new FlexLayout.LayoutParams() { Grow = 1 });
		scrollDemo.AddView(reservedCol, new FlexLayout.LayoutParams() { Grow = 1 });

		// Horizontal scroll
		let hScrollCol = new FlexLayout() { Direction = .Vertical, Spacing = 4 };
		hScrollCol.AddView(new Label("Horizontal") { VAlign = .Top });
		let scrollH = new ScrollView();
		scrollH.VScrollBarPolicy = .Always;
		scrollH.HScrollBarPolicy = .Always;
		scrollH.ScrollBarMode = .Reserved;
		let hContent = new FlexLayout() { Direction = .Horizontal, Spacing = 4 };
		for (int i = 0; i < 20; i++)
		{
			let @box = new ColorView(Color((uint8)(60 + i * 9), (uint8)(100 + i * 5), (uint8)(180 - i * 6), 255), 60, 60);
			hContent.AddView(@box);
		}
		scrollH.AddView(hContent);
		hScrollCol.AddView(scrollH, new FlexLayout.LayoutParams() { Grow = 1 });
		scrollDemo.AddView(hScrollCol, new FlexLayout.LayoutParams() { Grow = 1 });

		// === Tab 3: Layouts demo (closable) ===
		let layoutDemo = new FlexLayout() { Direction = .Vertical, Spacing = 4 };
		layoutDemo.Padding = .(8);
		tabView.AddTab("Layouts", layoutDemo, true);

		let gridDemo = new GridLayout();
		gridDemo.Columns.Add(.Flex(1));
		gridDemo.Columns.Add(.Flex(1));
		gridDemo.Columns.Add(.Flex(1));
		gridDemo.Rows.Add(.Flex(1));
		gridDemo.Rows.Add(.Flex(1));
		gridDemo.ColumnSpacing = 4;
		gridDemo.RowSpacing = 4;

		Color[?] gridColors = .(
			.(80, 60, 60, 255), .(60, 80, 60, 255), .(60, 60, 80, 255),
			.(70, 50, 50, 255), .(50, 70, 50, 255), .(50, 50, 70, 255)
		);
		for (int i = 0; i < 6; i++)
		{
			let cell = new ColorView(gridColors[i], 0, 0);
			gridDemo.AddView(cell, new GridLayout.LayoutParams() { Row = (int32)(i / 3), Column = (int32)(i % 3) });
		}
		layoutDemo.AddView(gridDemo, new FlexLayout.LayoutParams() { Grow = 1 });

		// === Tab 4: Tab Placement demo (closable) ===
		let tabPlacementDemo = new GridLayout();
		tabPlacementDemo.Columns.Add(.Flex(1));
		tabPlacementDemo.Columns.Add(.Flex(1));
		tabPlacementDemo.Rows.Add(.Flex(1));
		tabPlacementDemo.Rows.Add(.Flex(1));
		tabPlacementDemo.ColumnSpacing = 4;
		tabPlacementDemo.RowSpacing = 4;
		tabView.AddTab("Tab Placement", tabPlacementDemo, true);

		// Top placement
		let topTabs = new TabView() { Placement = .Top };
		topTabs.AddTab("Top A", new Label("Top placement A"));
		topTabs.AddTab("Top B", new Label("Top placement B"));
		tabPlacementDemo.AddView(topTabs, new GridLayout.LayoutParams() { Row = 0, Column = 0 });

		// Bottom placement
		let bottomTabs = new TabView() { Placement = .Bottom };
		bottomTabs.AddTab("Bot A", new Label("Bottom placement A"));
		bottomTabs.AddTab("Bot B", new Label("Bottom placement B"));
		tabPlacementDemo.AddView(bottomTabs, new GridLayout.LayoutParams() { Row = 0, Column = 1 });

		// Left placement
		let leftTabs = new TabView() { Placement = .Left };
		leftTabs.AddTab("Left A", new Label("Left placement A"));
		leftTabs.AddTab("Left B", new Label("Left placement B"));
		tabPlacementDemo.AddView(leftTabs, new GridLayout.LayoutParams() { Row = 1, Column = 0 });

		// Right placement
		let rightTabs = new TabView() { Placement = .Right };
		rightTabs.AddTab("Right A", new Label("Right placement A"));
		rightTabs.AddTab("Right B", new Label("Right placement B"));
		tabPlacementDemo.AddView(rightTabs, new GridLayout.LayoutParams() { Row = 1, Column = 1 });

		// Footer
		let footer = new ThemedBox("panel", 0, 24);
		main.AddView(footer, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(24)) });
	}

	protected override void OnInput(FrameContext frame)
	{
		// Update repeat button
		mRepeatBtn?.UpdateRepeat(frame.DeltaTime);

		let keyboard = Shell.InputManager.Keyboard;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		// Debug overlay toggles
		if (keyboard.IsKeyPressed(.F2))
			mUIContext.DebugSettings.ShowBounds = !mUIContext.DebugSettings.ShowBounds;
		if (keyboard.IsKeyPressed(.F3))
		{
			mUIContext.DebugSettings.ShowPadding = !mUIContext.DebugSettings.ShowPadding;
			mUIContext.DebugSettings.ShowMargin = !mUIContext.DebugSettings.ShowMargin;
		}
		if (keyboard.IsKeyPressed(.F4))
		{
			mUIContext.DebugSettings.ShowHitTarget = !mUIContext.DebugSettings.ShowHitTarget;
			mUIContext.DebugSettings.ShowFocusPath = !mUIContext.DebugSettings.ShowFocusPath;
		}
		// F5: cycle themes (Dark → Light → RoundedDark)
		if (keyboard.IsKeyPressed(.F5))
		{
			mThemeIndex = (mThemeIndex + 1) % 3;
			ApplyTheme();
		}
	}

	private void ApplyTheme()
	{
		StyleSheet sheet;
		switch (mThemeIndex)
		{
		case 0:  sheet = DarkTheme.Create(); mPalette = .Dark;
		case 1:  sheet = LightTheme.Create(); mPalette = .Light;
		default: sheet = RoundedDarkTheme.Create(); mPalette = .Dark;
		}
		mUIContext.StyleSheet = sheet;
		sheet.ReleaseRef();
	}

	private ThemePalette mPalette = .Dark;

	protected override bool OnRenderFrame(RenderContext render)
	{
		if (mUI == null || !mUI.IsRenderingInitialized)
			return false;

		// Clear with theme background color.
		let bg = mPalette.Background;
		ColorAttachment[1] clearAttachments = .(.()
		{
			View = render.CurrentTextureView,
			LoadOp = .Clear,
			StoreOp = .Store,
			ClearValue = ClearColor(bg.R / 255.0f, bg.G / 255.0f, bg.B / 255.0f, 1.0f)
		});
		RenderPassDesc clearDesc = .() { ColorAttachments = .(clearAttachments) };
		let clearPass = render.Encoder.BeginRenderPass(clearDesc);
		if (clearPass != null)
			clearPass.End();

		// Render UI overlay on top of cleared background.
		mUI.Render(render.Encoder, render.CurrentTextureView,
			render.SwapChain.Width, render.SwapChain.Height, render.Frame.FrameIndex);

		return true;
	}

	protected override void OnShutdown()
	{
		// Remove root from context before deletion (unregisters all views)
		if (mUIContext != null && mRoot != null)
			mUIContext.RemoveRootView(mRoot);

		// App owns UIContext and RootView — delete in reverse creation order
		if (mRoot != null)
		{
			delete mRoot;
			mRoot = null;
		}

		if (mUIContext != null)
		{
			delete mUIContext;
			mUIContext = null;
		}
	}

	/// Generate a checkerboard image for ImageView demo.
	private static OwnedImageData GenerateCheckerboard(int w, int h, int cellSize, Color c1, Color c2)
	{
		let data = new uint8[w * h * 4];
		for (int y = 0; y < h; y++)
		{
			for (int x = 0; x < w; x++)
			{
				let cell = ((x / cellSize) + (y / cellSize)) % 2 == 0;
				let c = cell ? c1 : c2;
				let offset = (y * w + x) * 4;
				data[offset] = c.R;
				data[offset + 1] = c.G;
				data[offset + 2] = c.B;
				data[offset + 3] = c.A;
			}
		}
		return new OwnedImageData((.)w, (.)h, .RGBA8, data);
	}
}

/// Simple colored rectangle view for layout demos.
class ColorBox : View
{
	public Color Color;
	private float mDesiredW;
	private float mDesiredH;

	public this(Color color, float desiredW = 0, float desiredH = 0)
	{
		Color = color;
		mDesiredW = desiredW;
		mDesiredH = desiredH;
	}

	protected override void OnMeasure(BoxConstraints constraints)
	{
		let w = (mDesiredW > 0) ? mDesiredW : constraints.MaxWidth;
		let h = (mDesiredH > 0) ? mDesiredH : constraints.MaxHeight;
		MeasuredSize = .(constraints.ConstrainWidth(w), constraints.ConstrainHeight(h));
	}

	public override void OnDraw(UIDrawContext ctx)
	{
		ctx.VG.FillRect(.(0, 0, Width, Height), Color);
	}
}

/// View that draws its background from the theme via StyleSheet.
/// Set StyleId to match a theme rule (e.g., "panel", "button").
class ThemedBox : View
{
	private float mDesiredW;
	private float mDesiredH;

	public this(StringView styleClass, float desiredW = 0, float desiredH = 0)
	{
		StyleId = new String(styleClass);
		mDesiredW = desiredW;
		mDesiredH = desiredH;
	}

	protected override void OnMeasure(BoxConstraints constraints)
	{
		let w = (mDesiredW > 0) ? mDesiredW : constraints.MaxWidth;
		let h = (mDesiredH > 0) ? mDesiredH : constraints.MaxHeight;
		MeasuredSize = .(constraints.ConstrainWidth(w), constraints.ConstrainHeight(h));
	}

	public override void OnDraw(UIDrawContext ctx)
	{
		let bounds = RectangleF(0, 0, Width, Height);

		// Try drawable from stylesheet first.
		let drawable = ResolveStyleDrawable(.Background);
		if (drawable != null)
		{
			drawable.Draw(ctx, bounds, GetControlState());
			return;
		}

		// Fallback: fill with resolved background color or surface.
		let bgColor = ResolveStyleColor(.TextColor, .(50, 52, 60, 255));
		ctx.VG.FillRect(bounds, Palette.Darken(bgColor, 0.7f));
	}
}
