namespace UI2Sandbox;

using System;
using Sedulous.Runtime;
using Sedulous.Runtime.Client;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell.Input;
using Sedulous.UI2;
using Sedulous.UI2.Runtime;

/// Minimal UI2 sandbox application. Extends Application directly (no engine).
/// App owns UIContext and RootView. Subsystem owns rendering pipeline.
class UI2SandboxApp : Application
{
	// Subsystem (registered with Context, cleaned up by Context)
	private UI2Subsystem mUI;

	// App-owned UI state (cleaned up in OnShutdown)
	private UIContext mUIContext;
	private RootView mRoot;

	protected override void OnInitialize(Context context)
	{
		// Create app-owned UI state
		mUIContext = new UIContext();
		mRoot = new RootView();

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

		// Build initial UI
		BuildUI();

		Console.WriteLine("=== UI2 Sandbox Ready ===");
	}

	private void BuildUI()
	{
		// Main vertical layout filling the window
		let main = new FlexLayout() { Direction = .Vertical };
		mRoot.AddView(main);

		// Header
		let header = new ColorBox(.(40, 42, 50, 255), 0, 36);
		main.AddView(header, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(36)) });

		// Body: horizontal split
		let body = new FlexLayout() { Direction = .Horizontal, Spacing = 2 };
		main.AddView(body, new FlexLayout.LayoutParams() { Width = .Match, Grow = 1 });

		// Left panel — DockLayout demo
		let leftPanel = new DockLayout();
		leftPanel.Padding = .(4);
		body.AddView(leftPanel, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(250)), Height = .Match });

		let dockTop = new ColorBox(.(60, 130, 60, 255), 240, 30);
		leftPanel.AddView(dockTop, new DockLayout.LayoutParams(.Top));

		let dockBottom = new ColorBox(.(130, 60, 60, 255), 240, 30);
		leftPanel.AddView(dockBottom, new DockLayout.LayoutParams(.Bottom));

		let dockLeft = new ColorBox(.(60, 60, 130, 255), 50, 0);
		leftPanel.AddView(dockLeft, new DockLayout.LayoutParams(.Left));

		let dockCenter = new ColorBox(.(50, 52, 58, 255));
		leftPanel.AddView(dockCenter, new DockLayout.LayoutParams(.Fill));

		// Center panel — Grid demo
		let centerPanel = new GridLayout();
		centerPanel.Columns.Add(.Flex(1));
		centerPanel.Columns.Add(.Flex(2));
		centerPanel.Columns.Add(.Flex(1));
		centerPanel.Rows.Add(.Fixed(40));
		centerPanel.Rows.Add(.Flex(1));
		centerPanel.Rows.Add(.Fixed(40));
		centerPanel.ColumnSpacing = 2;
		centerPanel.RowSpacing = 2;
		body.AddView(centerPanel, new FlexLayout.LayoutParams() { Grow = 1, Height = .Match });

		// Fill grid cells with colored boxes
		Color[?] gridColors = .(
			.(80, 60, 60, 255), .(60, 80, 60, 255), .(60, 60, 80, 255),
			.(70, 50, 50, 255), .(50, 70, 50, 255), .(50, 50, 70, 255),
			.(90, 70, 70, 255), .(70, 90, 70, 255), .(70, 70, 90, 255)
		);
		for (int r = 0; r < 3; r++)
		{
			for (int c = 0; c < 3; c++)
			{
				let cell = new ColorBox(gridColors[r * 3 + c]);
				centerPanel.AddView(cell, new GridLayout.LayoutParams() { Row = (int32)r, Column = (int32)c });
			}
		}

		// Right panel — FlowLayout demo
		let rightPanel = new FlowLayout() { Orientation = .Horizontal, HSpacing = 4, VSpacing = 4 };
		rightPanel.Padding = .(4);
		body.AddView(rightPanel, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(200)), Height = .Match });

		Color[?] flowColors = .(
			.(100, 60, 80, 255), .(60, 100, 80, 255), .(80, 60, 100, 255),
			.(100, 80, 60, 255), .(60, 80, 100, 255), .(80, 100, 60, 255),
			.(90, 70, 90, 255), .(70, 90, 70, 255)
		);
		for (int i = 0; i < flowColors.Count; i++)
		{
			let size = 30 + (i % 3) * 15;
			let @box = new ColorBox(flowColors[i], (float)size, (float)size);
			rightPanel.AddView(@box);
		}

		// Footer
		let footer = new ColorBox(.(35, 37, 43, 255), 0, 24);
		main.AddView(footer, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(24)) });
	}

	protected override void OnInput(FrameContext frame)
	{
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
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		if (mUI == null || !mUI.IsRenderingInitialized)
			return false;

		// Clear the backbuffer first (no 3D scene to preserve).
		ColorAttachment[1] clearAttachments = .(.()
		{
			View = render.CurrentTextureView,
			LoadOp = .Clear,
			StoreOp = .Store,
			ClearValue = .(0, 0, 0, 1)
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
		// If desired size is 0, fill available space.
		let w = (mDesiredW > 0) ? mDesiredW : constraints.MaxWidth;
		let h = (mDesiredH > 0) ? mDesiredH : constraints.MaxHeight;
		MeasuredSize = .(constraints.ConstrainWidth(w), constraints.ConstrainHeight(h));
	}

	public override void OnDraw(UIDrawContext ctx)
	{
		ctx.VG.FillRect(.(0, 0, Width, Height), Color);
	}
}
