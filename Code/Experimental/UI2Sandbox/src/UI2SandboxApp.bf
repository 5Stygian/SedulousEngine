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
		mUI.LoadFont("Roboto", fontPath, .()
			{
				PixelHeight = 16, FirstCodepoint = 32,
				LastCodepoint = 255,
				AtlasWidth = 1024,
				AtlasHeight = 1024,
				OversampleX = 2,
				OversampleY = 2,
				Padding = 2
			});
		mUI.LoadFont("Roboto", fontPath, .()
			{
				PixelHeight = 24, FirstCodepoint = 32,
				LastCodepoint = 255,
				AtlasWidth = 1024,
				AtlasHeight = 1024,
				OversampleX = 2,
				OversampleY = 2,
				Padding = 2
			});

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

		// === Tab 5: Text Input demo ===
		let textInputScroll = new ScrollView();
		textInputScroll.VScrollBarPolicy = .Auto;
		tabView.AddTab("Text Input", textInputScroll);

		let textInputDemo = new FlexLayout() { Direction = .Vertical, Spacing = 8 };
		textInputDemo.Padding = .(12, 8);
		textInputScroll.AddView(textInputDemo);

		// --- EditText section ---
		textInputDemo.AddView(new Label("EditText"));
		textInputDemo.AddView(new Separator());

		let editBasic = new EditText();
		editBasic.SetText("Editable text");
		textInputDemo.AddView(editBasic, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(300)) });

		let editPlaceholder = new EditText();
		editPlaceholder.SetPlaceholder("Enter name...");
		textInputDemo.AddView(editPlaceholder, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(300)) });

		let editReadOnly = new EditText();
		editReadOnly.SetText("Read-only text");
		editReadOnly.IsReadOnly = true;
		textInputDemo.AddView(editReadOnly, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(300)) });

		let editMultiline = new EditText();
		editMultiline.Multiline = true;
		editMultiline.SetText("Line 1\nLine 2\nLine 3");
		textInputDemo.AddView(editMultiline, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(300)), Height = .Fixed(.Px(80)) });

		let editMaxLen = new EditText();
		editMaxLen.MaxLength = 10;
		editMaxLen.SetPlaceholder("Max 10 chars");
		textInputDemo.AddView(editMaxLen, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(300)) });

		let editDigits = new EditText();
		editDigits.Filter = InputFilter.Digits();
		editDigits.SetPlaceholder("Digits only");
		textInputDemo.AddView(editDigits, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(300)) });

		let editPrefix = new EditText();
		editPrefix.SetPrefix("$");
		editPrefix.SetText("100");
		textInputDemo.AddView(editPrefix, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(300)) });

		let editSuffix = new EditText();
		editSuffix.SetSuffix("px");
		editSuffix.SetText("16");
		textInputDemo.AddView(editSuffix, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(300)) });

		// --- PasswordBox section ---
		textInputDemo.AddView(new Spacer(0, 4));
		textInputDemo.AddView(new Label("PasswordBox"));
		textInputDemo.AddView(new Separator());

		let pw1 = new PasswordBox();
		pw1.SetPlaceholder("Password");
		textInputDemo.AddView(pw1, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(300)) });

		let pw2 = new PasswordBox();
		pw2.PasswordChar = '\u{25CF}'; // ● bullet
		pw2.SetPlaceholder("Custom mask");
		textInputDemo.AddView(pw2, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(300)) });

		// --- NumericField section ---
		textInputDemo.AddView(new Spacer(0, 4));
		textInputDemo.AddView(new Label("NumericField"));
		textInputDemo.AddView(new Separator());

		let nfDefault = new NumericField();
		nfDefault.Min = 0;
		nfDefault.Max = 100;
		nfDefault.Value = 42;
		textInputDemo.AddView(nfDefault, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(200)) });

		let nfNoSpin = new NumericField();
		nfNoSpin.Min = 0;
		nfNoSpin.Max = 100;
		nfNoSpin.ShowSpinButtons = false;
		nfNoSpin.Value = 25;
		textInputDemo.AddView(nfNoSpin, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(200)) });

		let nfConstrained = new NumericField();
		nfConstrained.Min = -10;
		nfConstrained.Max = 10;
		nfConstrained.Step = 0.5;
		nfConstrained.DecimalPlaces = 1;
		nfConstrained.Value = 0;
		textInputDemo.AddView(nfConstrained, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(200)) });

		let nfInteger = new NumericField();
		nfInteger.Min = 0;
		nfInteger.Max = 999;
		nfInteger.DecimalPlaces = 0;
		nfInteger.Value = 100;
		textInputDemo.AddView(nfInteger, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(200)) });

		let nfSuffix = new NumericField();
		nfSuffix.Min = 0;
		nfSuffix.Max = 360;
		nfSuffix.DecimalPlaces = 1;
		nfSuffix.SetSuffix("\u{00B0}"); // degree sign
		nfSuffix.Value = 90;
		textInputDemo.AddView(nfSuffix, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(200)) });

		// Vector3-style editor: 3 numeric fields with colored prefix labels
		textInputDemo.AddView(new Label("Vector3 Editor"));
		let vecRow = new FlexLayout() { Direction = .Horizontal, Spacing = 4 };

		void AddAxisField(FlexLayout row, StringView axis, Color axisColor, double val)
		{
			let nf = new NumericField();
			nf.Min = -999;
			nf.Max = 999;
			nf.Step = 0.1;
			nf.DecimalPlaces = 2;
			nf.ShowSpinButtons = false;
			nf.Value = val;
			let prefixView = new ColoredLabel(axis, axisColor);
			nf.SetPrefix(prefixView);
			row.AddView(nf, new FlexLayout.LayoutParams() { Grow = 1 });
		}

		AddAxisField(vecRow, "X", .(220, 80, 80, 255), 1.06);
		AddAxisField(vecRow, "Y", .(80, 200, 80, 255), 0.0);
		AddAxisField(vecRow, "Z", .(80, 120, 220, 255), 2.17);
		textInputDemo.AddView(vecRow, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(400)) });

		// --- EditableLabel section ---
		textInputDemo.AddView(new Spacer(0, 4));
		textInputDemo.AddView(new Label("EditableLabel (double-click to edit)"));
		textInputDemo.AddView(new Separator());

		let el1 = new EditableLabel();
		el1.SetText("Double-click me");
		el1.SlowClickToEdit = false;
		textInputDemo.AddView(el1, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(300)) });

		let el2 = new EditableLabel();
		el2.SetText("Slow-click me");
		el2.DoubleClickToEdit = false;
		textInputDemo.AddView(el2, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(300)) });

		let el3 = new EditableLabel();
		el3.SetText("With validation");
		el3.ValidateRename = new (text) => !text.Contains("bad");
		textInputDemo.AddView(el3, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(300)) });

		// === Tab 6: Overlays demo ===
		let overlaysScroll = new ScrollView();
		overlaysScroll.VScrollBarPolicy = .Auto;
		tabView.AddTab("Overlays", overlaysScroll);

		let overlaysDemo = new FlexLayout() { Direction = .Vertical, Spacing = 8 };
		overlaysDemo.Padding = .(12, 8);
		overlaysScroll.AddView(overlaysDemo);

		// --- ComboBox section ---
		overlaysDemo.AddView(new Label("ComboBox"));
		overlaysDemo.AddView(new Separator());

		let comboBasic = new ComboBox();
		comboBasic.AddItem("Option 1");
		comboBasic.AddItem("Option 2");
		comboBasic.AddItem("Option 3");
		overlaysDemo.AddView(comboBasic, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(200)) });

		let comboPreselected = new ComboBox();
		comboPreselected.AddItem("Red");
		comboPreselected.AddItem("Green");
		comboPreselected.AddItem("Blue");
		comboPreselected.SelectedIndex = 1;
		overlaysDemo.AddView(comboPreselected, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(200)) });

		// --- Dialog section ---
		overlaysDemo.AddView(new Spacer(0, 4));
		overlaysDemo.AddView(new Label("Dialog"));
		overlaysDemo.AddView(new Separator());

		let dialogRow = new FlexLayout() { Direction = .Horizontal, Spacing = 8 };

		let alertBtn = new Button("Alert");
		alertBtn.OnClick.Add(new (b) =>
		{
			let dlg = Dialog.Alert("Information", "This is an alert dialog.");
			dlg.Show(mUIContext);
		});
		dialogRow.AddView(alertBtn);

		let confirmBtn = new Button("Confirm");
		confirmBtn.OnClick.Add(new (b) =>
		{
			let dlg = Dialog.Confirm("Confirm", "Are you sure you want to proceed?");
			dlg.Show(mUIContext);
		});
		dialogRow.AddView(confirmBtn);
		overlaysDemo.AddView(dialogRow);

		// --- ContextMenu section ---
		overlaysDemo.AddView(new Spacer(0, 4));
		overlaysDemo.AddView(new Label("ContextMenu (right-click below)"));
		overlaysDemo.AddView(new Separator());

		let contextArea = new ContextMenuDemoArea();
		overlaysDemo.AddView(contextArea, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(80)) });

		// --- Tooltip section ---
		overlaysDemo.AddView(new Spacer(0, 4));
		overlaysDemo.AddView(new Label("Tooltips (hover below)"));
		overlaysDemo.AddView(new Separator());

		let tooltipRow = new FlexLayout() { Direction = .Horizontal, Spacing = 8 };
		let ttBtn1 = new Button("Bottom tooltip");
		ttBtn1.TooltipText = new String("This appears below");
		tooltipRow.AddView(ttBtn1);

		let ttBtn2 = new Button("Top tooltip");
		ttBtn2.TooltipText = new String("This appears above");
		ttBtn2.TooltipPlacement = .Top;
		tooltipRow.AddView(ttBtn2);

		let ttBtn3 = new Button("Right tooltip");
		ttBtn3.TooltipText = new String("This appears on the right");
		ttBtn3.TooltipPlacement = .Right;
		tooltipRow.AddView(ttBtn3);

		let ttBtn4 = new Button("Interactive");
		ttBtn4.TooltipText = new String("This tooltip stays while you hover it");
		ttBtn4.IsTooltipInteractive = true;
		tooltipRow.AddView(ttBtn4);

		let ttBtn5 = new RichTooltipButton("Rich content");
		tooltipRow.AddView(ttBtn5);
		overlaysDemo.AddView(tooltipRow);

		// === Tab 7: Drag & Drop demo ===
		let dndDemo = new FlexLayout() { Direction = .Vertical, Spacing = 8 };
		dndDemo.Padding = .(12, 8);
		tabView.AddTab("Drag & Drop", dndDemo);

		dndDemo.AddView(new Label("Drag chips to reorder, or drop onto the box"));
		dndDemo.AddView(new Separator());

		let dndRow = new FlexLayout() { Direction = .Horizontal, Spacing = 8 };

		let chipContainer = new ChipReorderContainer();
		chipContainer.Direction = .Horizontal;
		chipContainer.Spacing = 4;

		Color[?] chipColors = .(
			.(220, 60, 60, 255), .(60, 180, 60, 255), .(60, 100, 220, 255),
			.(220, 180, 40, 255), .(180, 60, 220, 255));
		for (int i = 0; i < chipColors.Count; i++)
		{
			let chip = new DragChip(chipColors[i]);
			chipContainer.AddView(chip, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(30)), Height = .Fixed(.Px(30)) });
		}
		dndRow.AddView(chipContainer);

		let dropBox = new ColorDropBox();
		dndRow.AddView(dropBox, new FlexLayout.LayoutParams() { Grow = 1, Height = .Fixed(.Px(30)) });
		dndDemo.AddView(dndRow);

		// === Tab 8: Animations & Transforms demo ===
		let animDemo = new FlexLayout() { Direction = .Vertical, Spacing = 8 };
		animDemo.Padding = .(12, 8);
		tabView.AddTab("Animations", animDemo);

		// Animation target
		animDemo.AddView(new Label("Animation Target"));
		let animTarget = new ColorView(.(80, 160, 255, 255), 0, 30);
		animDemo.AddView(animTarget, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(30)) });

		// Animation buttons
		let animRow = new FlexLayout() { Direction = .Horizontal, Spacing = 6 };

		let fadeOutBtn = new Button("Fade Out");
		fadeOutBtn.OnClick.Add(new (b) =>
		{
			mUIContext.Animations.Add(ViewAnimator.FadeOut(animTarget, 0.5f, Easing.EaseOutCubic));
		});
		animRow.AddView(fadeOutBtn);

		let fadeInBtn = new Button("Fade In");
		fadeInBtn.OnClick.Add(new (b) =>
		{
			mUIContext.Animations.Add(ViewAnimator.FadeIn(animTarget, 0.5f, Easing.EaseOutCubic));
		});
		animRow.AddView(fadeInBtn);

		let bounceBtn = new Button("Bounce");
		bounceBtn.OnClick.Add(new (b) =>
		{
			let sb = new Storyboard(.Sequential);
			sb.Add(ViewAnimator.ScaleTo(animTarget, 1.0f, 1.3f, 0.15f, Easing.EaseOutCubic));
			sb.Add(ViewAnimator.ScaleTo(animTarget, 1.3f, 1.0f, 0.3f, Easing.BounceOut));
			mUIContext.Animations.Add(sb);
		});
		animRow.AddView(bounceBtn);

		let slideBtn = new Button("Slide");
		slideBtn.OnClick.Add(new (b) =>
		{
			let sb = new Storyboard(.Sequential);
			sb.Add(ViewAnimator.TranslateX(animTarget, 0, 50, 0.3f, Easing.EaseOutCubic));
			sb.Add(ViewAnimator.TranslateX(animTarget, 50, 0, 0.3f, Easing.EaseInCubic));
			mUIContext.Animations.Add(sb);
		});
		animRow.AddView(slideBtn);
		animDemo.AddView(animRow);

		// Transform demos
		animDemo.AddView(new Spacer(0, 8));
		animDemo.AddView(new Label("Static Transforms (click to verify hit-testing)"));
		animDemo.AddView(new Separator());

		let transformClickLabel = new Label("Click a transformed button...");
		let transformRow = new FlexLayout() { Direction = .Horizontal, Spacing = 16 };

		let rotBtn = new Button("Rotated");
		rotBtn.Transform = .() { Rotation = 0.15f };
		rotBtn.OnClick.Add(new (b) => { transformClickLabel.SetText("Rotated button clicked!"); });
		transformRow.AddView(rotBtn);

		let scaleBtn = new Button("Scaled 1.2x");
		scaleBtn.Transform = .() { Scale = .(1.2f, 1.2f) };
		scaleBtn.OnClick.Add(new (b) => { transformClickLabel.SetText("Scaled button clicked!"); });
		transformRow.AddView(scaleBtn);

		let skewTranslateBtn = new Button("Translated");
		skewTranslateBtn.Transform = .() { Translation = .(10, 5) };
		skewTranslateBtn.OnClick.Add(new (b) => { transformClickLabel.SetText("Translated button clicked!"); });
		transformRow.AddView(skewTranslateBtn);

		animDemo.AddView(transformRow);
		animDemo.AddView(transformClickLabel);

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

/// Small text label with a specific color, used as a prefix View in NumericField.
class ColoredLabel : View
{
	private String mText ~ delete _;
	private Color mColor;

	public this(StringView text, Color color)
	{
		mText = new String(text);
		mColor = color;
	}

	protected override void OnMeasure(BoxConstraints constraints)
	{
		let fontSize = ResolveStyleFloat(.FontSize, 14);
		float w = 12, h = fontSize;
		if (Context?.FontService != null)
		{
			let font = Context.FontService.GetFont(fontSize);
			if (font != null)
			{
				w = font.Font.MeasureString(mText);
				h = font.Font.Metrics.LineHeight;
			}
		}
		MeasuredSize = .(constraints.ConstrainWidth(w), constraints.ConstrainHeight(h));
	}

	public override void OnDraw(UIDrawContext ctx)
	{
		let fontSize = ResolveStyleFloat(.FontSize, 14);
		let font = ctx.FontService?.GetFont(fontSize);
		if (font != null)
			ctx.VG.DrawText(mText, font, .(0, 0, Width, Height), .Center, .Middle, mColor);
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

/// Demo area that shows a ContextMenu on right-click.
class ContextMenuDemoArea : View
{
	protected override void OnMeasure(BoxConstraints constraints)
	{
		MeasuredSize = .(constraints.ConstrainWidth(constraints.MaxWidth),
			constraints.ConstrainHeight(80));
	}

	public override void OnDraw(UIDrawContext ctx)
	{
		let bounds = RectangleF(0, 0, Width, Height);
		let bg = ResolveStyleColor(.BorderColor, .(50, 55, 65, 255));
		ctx.VG.FillRoundedRect(bounds, 4, Palette.Darken(bg, 0.3f));
		ctx.VG.StrokeRoundedRect(bounds, 4, bg, 1);
		if (ctx.FontService != null)
		{
			let font = ctx.FontService.GetFont(14);
			if (font != null)
				ctx.VG.DrawText("Right-click for context menu", font,
					bounds, .Center, .Middle, .(180, 185, 200, 255));
		}
	}

	public override void OnMouseDown(MouseEventArgs e)
	{
		if (e.Button == .Right && Context != null)
		{
			let menu = new ContextMenu();
			menu.AddItem("Cut", new () => {});
			menu.AddItem("Copy", new () => {});
			menu.AddItem("Paste", new () => {});
			menu.AddSeparator();
			let sub = menu.AddSubmenu("More");
			sub.Submenu.AddItem("Select All", new () => {});
			sub.Submenu.AddItem("Find", new () => {});
			sub.Submenu.AddSeparator();
			let nested = sub.Submenu.AddSubmenu("Even More");
			nested.Submenu.AddItem("Nested Item 1", new () => {});
			nested.Submenu.AddItem("Nested Item 2", new () => {});
			menu.AddSeparator();
			menu.AddItem("Disabled Item", new () => {}, false);

			let screenPos = LocalToScreen(.(e.X, e.Y));
			menu.Show(Context, screenPos.X, screenPos.Y);
			e.Handled = true;
		}
	}
}

/// Custom drag data carrying a reference to the source chip.
class ChipDragData : DragData
{
	public DragChip SourceChip;

	public this(DragChip source) : base("demo/chip")
	{
		SourceChip = source;
	}
}

/// Draggable colored chip implementing IDragSource.
class DragChip : ColorView, IDragSource
{
	public this(Color color) : base(color, 30, 30) { }

	public DragData CreateDragData()
	{
		return new ChipDragData(this);
	}

	public View CreateDragVisual(DragData data)
	{
		let panel = new Panel();
		panel.Padding = .(6, 2);
		let label = new Label(scope String()..AppendF("#{0:X2}{1:X2}{2:X2}", Color.R, Color.G, Color.B));
		panel.AddView(label);
		return panel;
	}

	public void OnDragStarted(DragData data) { Opacity = 0.4f; }
	public void OnDragCompleted(DragData data, DragDropEffects effect, bool cancelled) { Opacity = 1.0f; }
}

/// Container that accepts chip drops and reorders by swapping colors.
class ChipReorderContainer : FlexLayout, IDropTarget
{
	public DragDropEffects CanAcceptDrop(DragData data, float localX, float localY)
	{
		return (data.Format == "demo/chip") ? .Move : .None;
	}

	public void OnDragEnter(DragData data, float localX, float localY) { }
	public void OnDragOver(DragData data, float localX, float localY) { }
	public void OnDragLeave(DragData data) { }

	public DragDropEffects OnDrop(DragData data, float localX, float localY)
	{
		if (let chipData = data as ChipDragData)
		{
			let sourceChip = chipData.SourceChip;
			for (int i = 0; i < ChildCount; i++)
			{
				let child = GetChildAt(i);
				if (localX >= child.Bounds.X && localX < child.Bounds.X + child.Width)
				{
					if (let targetChip = child as DragChip)
					{
						if (targetChip !== sourceChip)
						{
							let tempColor = sourceChip.Color;
							sourceChip.Color = targetChip.Color;
							targetChip.Color = tempColor;
						}
						return .Move;
					}
				}
			}
		}
		return .None;
	}
}

/// Drop target box that changes color when a chip is dropped on it.
class ColorDropBox : View, IDropTarget
{
	private String mText = new .("Drop here") ~ delete _;
	private Color mBgColor = .(50, 55, 65, 255);

	protected override void OnMeasure(BoxConstraints constraints)
	{
		MeasuredSize = .(constraints.ConstrainWidth(constraints.MaxWidth),
			constraints.ConstrainHeight(30));
	}

	public override void OnDraw(UIDrawContext ctx)
	{
		let bounds = RectangleF(0, 0, Width, Height);
		ctx.VG.FillRoundedRect(bounds, 4, mBgColor);
		ctx.VG.StrokeRoundedRect(bounds, 4, .(70, 75, 85, 255), 1);
		if (ctx.FontService != null)
		{
			let font = ctx.FontService.GetFont(12);
			if (font != null)
				ctx.VG.DrawText(mText, font, bounds, .Center, .Middle, .(220, 225, 235, 255));
		}
	}

	public DragDropEffects CanAcceptDrop(DragData data, float localX, float localY)
	{
		return (data.Format == "demo/chip") ? .Copy : .None;
	}

	public void OnDragEnter(DragData data, float localX, float localY) { mText.Set("Release!"); Invalidate(); }
	public void OnDragOver(DragData data, float localX, float localY) { }
	public void OnDragLeave(DragData data) { mText.Set("Drop here"); Invalidate(); }

	public DragDropEffects OnDrop(DragData data, float localX, float localY)
	{
		if (let chipData = data as ChipDragData)
		{
			mBgColor = chipData.SourceChip.Color;
			mText.Set("Dropped!");
			Invalidate();
		}
		return .Copy;
	}
}

/// Button that provides rich tooltip content via ITooltipProvider.
class RichTooltipButton : Button, ITooltipProvider
{
	public this(StringView text) : base(text)
	{
		IsTooltipInteractive = true;
	}

	public View CreateTooltipContent()
	{
		let layout = new FlexLayout() { Direction = .Vertical, Spacing = 4 };
		layout.AddView(new Label("Rich Tooltip"));
		layout.AddView(new Separator());
		layout.AddView(new Label("This tooltip has multiple lines,") { StyleId = new String("label-dim") });
		layout.AddView(new Label("a separator, and custom content.") { StyleId = new String("label-dim") });
		let colorRow = new FlexLayout() { Direction = .Horizontal, Spacing = 4 };
		colorRow.AddView(new ColorView(.(220, 60, 60, 255), 16, 16));
		colorRow.AddView(new ColorView(.(60, 180, 60, 255), 16, 16));
		colorRow.AddView(new ColorView(.(60, 60, 220, 255), 16, 16));
		layout.AddView(colorRow);
		return layout;
	}
}
