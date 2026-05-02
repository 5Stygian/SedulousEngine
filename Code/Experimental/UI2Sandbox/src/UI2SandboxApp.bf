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
		// Add a simple demo view that draws a dark background with text
		let demoView = new DemoView();
		mRoot.AddView(demoView);
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

/// Simple demo view that fills with a dark background and draws text.
/// Temporary — will be replaced by real controls in later phases.
class DemoView : View
{
	protected override void OnMeasure(BoxConstraints constraints)
	{
		MeasuredSize = .(constraints.ConstrainWidth(constraints.MaxWidth),
			constraints.ConstrainHeight(constraints.MaxHeight));
	}

	public override void OnDraw(UIDrawContext ctx)
	{
		let bounds = RectangleF(0, 0, Width, Height);

		// Dark background
		ctx.VG.FillRect(bounds, .(30, 32, 38, 255));

		// Title text
		if (ctx.FontService != null)
		{
			let font = ctx.FontService.GetFont(24);
			if (font != null)
				ctx.VG.DrawText("UI2 Sandbox", font, .(20, 20, Width - 40, 30), .Left, .Top, .(220, 220, 230, 255));

			let smallFont = ctx.FontService.GetFont(16);
			if (smallFont != null)
			{
				ctx.VG.DrawText("F2: Toggle Bounds | F3: Padding/Margin | F4: Hit/Focus | Esc: Quit",
					smallFont, .(20, 56, Width - 40, 20), .Left, .Top, .(140, 140, 150, 255));

				ctx.VG.DrawText(scope String()..AppendF("Viewport: {}x{} | DPI: {:.1}",
					(int)Width, (int)Height, Root?.DpiScale ?? 1.0f),
					smallFont, .(20, 80, Width - 40, 20), .Left, .Top, .(100, 100, 110, 255));
			}
		}
	}
}
