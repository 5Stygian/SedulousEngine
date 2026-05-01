namespace TowerDefense;

using System;
using Sedulous.Engine.App;
using Sedulous.Engine.Core;
using Sedulous.Engine.Render;
using Sedulous.Runtime;
using Sedulous.Renderer;
using Sedulous.Renderer.Passes;
using Sedulous.Core.Mathematics;
using Sedulous.Materials;
using Sedulous.Resources;
using Sedulous.Shell.Input;
using Sedulous.Images.STB;
using Sedulous.Images.SDL;
using Sedulous.Messaging.Runtime;
using Sedulous.Engine;
using Sedulous.Engine.UI;
using Sedulous.UI;

class TowerDefenseApp : EngineApplication
{
	// Game subsystem
	private GameSubsystem mGameSub;

	// Scene
	private Scene mScene;

	// Model loading
	private ModelRegistry mModels = new .() ~ delete _;

	// Camera
	private TDCameraController mCamera = new .() ~ delete _;

	// Tower placement
	private TowerPlacement mTowerPlacement = new .() ~ delete _;

	// UI
	private HUDManager mHUD = new .() ~ delete _;
	private TowerSelectionPanel mTowerPanel = new .() ~ delete _;
	private MainMenuUI mMainMenu = new .() ~ delete _;
	private GameOverUI mGameOverUI = new .() ~ delete _;

	// ==================== Configuration ====================

	protected override void OnConfigure(Context context)
	{
		// Register messaging subsystem (drains at -500)
		context.RegisterSubsystem<MessagingSubsystem>(new MessagingSubsystem());

		// Register game subsystem (state + scene injection at -200)
		mGameSub = new GameSubsystem();
		context.RegisterSubsystem<GameSubsystem>(mGameSub);

		// Models and Resources will be set in OnStartup after they're available
	}

	// ==================== Startup ====================

	protected override void OnStartup()
	{
		Console.WriteLine("=== Tower Defense OnStartup ===");

		// Initialize image and model loaders
		SDLImageLoader.Initialize();
		STBImageLoader.Initialize();

		let sceneSub = Context.GetSubsystem<SceneSubsystem>();
		let renderSub = Context.GetSubsystem<RenderSubsystem>();
		let resources = ResourceSystem;

		// Initialize model registry (FBX loader) with resolved asset path
		let assetPath = scope String();
		GetAssetPath("samples/models/kenney_tower-defense-kit/Models/FBX format", assetPath);
		mModels.Initialize(assetPath);

		// Pass references to game subsystem for enemy spawning
		mGameSub.Models = mModels;
		mGameSub.Resources = resources;

		// Preload all models
		mModels.PreloadModels(resources, StringView[](
			// Tiles
			"tile", "tile-straight", "tile-rock",
			"tile-spawn-round", "tile-end-round",
			"tile-corner-round", "selection-a",
			// Enemies
			"enemy-ufo-a", "enemy-ufo-b", "enemy-ufo-c", "enemy-ufo-d",
			// Towers
			"tower-round-base", "tower-square-bottom-a",
			// Weapons
			"weapon-ballista", "weapon-cannon", "weapon-catapult", "weapon-turret",
			// Ammo
			"weapon-ammo-arrow", "weapon-ammo-cannonball", "weapon-ammo-boulder", "weapon-ammo-bullet"
		));

		// Create scene (triggers GameSubsystem.OnSceneCreated which injects EnemyComponentManager)
		mScene = sceneSub.CreateScene("GameScene");

		// Create camera
		mCamera.CameraEntity = mScene.CreateEntity("Camera");
		let cameraMgr = mScene.GetModule<CameraComponentManager>();
		if (cameraMgr != null)
			cameraMgr.CreateComponent(mCamera.CameraEntity);

		// Set initial camera position centered on map
		mCamera.LookTarget = .(6, 0, 6);
		mCamera.Zoom = 14.0f;
		mCamera.ApplyToScene(mScene);

		// Directional light
		let lightEntity = mScene.CreateEntity("Sun");
		mScene.SetLocalTransform(lightEntity, Transform.CreateLookAt(.(10, 15, 10), .Zero));

		let lightMgr = mScene.GetModule<LightComponentManager>();
		if (lightMgr != null)
		{
			let lightHandle = lightMgr.CreateComponent(lightEntity);
			if (let light = lightMgr.Get(lightHandle))
			{
				light.Type = .Directional;
				light.Color = .(1.0f, 0.95f, 0.85f);
				light.Intensity = 1.2f;
				light.CastsShadows = true;
			}
		}

		// Build the map (MapSystem takes ownership of MapData)
		mGameSub.Map.BuildMap(MapData.CreateMap1(), mScene, mModels, resources);

		// Update enemy waypoints now that the map is built
		mGameSub.UpdateWaypoints();

		// Reduce ambient lighting for better contrast with shadows
		renderSub.RenderContext.LightBuffer.AmbientColor = .(0.05f, 0.05f, 0.08f);

		// Set up UI
		SetupUI();

		Console.WriteLine("=== Tower Defense Ready ===");
	}

	// ==================== Update ====================

	protected override void OnUpdate(float deltaTime)
	{
		if (mScene == null)
			return;

		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		// Camera controls
		mCamera.Update(deltaTime, keyboard, mouse);
		mCamera.ApplyToScene(mScene);

		// Enter to start playing (from main menu - enables all gameplay interaction)
		if (keyboard.IsKeyPressed(.Return) && mGameSub.Phase == .MainMenu)
		{
			mGameSub.SetPhase(.Playing);
			mMainMenu.Hide();
			mTowerPanel.SetVisible(true);
			Console.WriteLine("[Game] Playing - place towers, then press Space to start wave");
		}

		// Everything below requires Playing phase
		if (mGameSub.Phase == .Playing)
		{
			// Space to start next wave
			if (keyboard.IsKeyPressed(.Space) && !mGameSub.Waves.IsWaveActive)
			{
				Console.WriteLine("[Input] Starting wave");
				mGameSub.Waves.StartNextWave();
			}

			// Tower selection (1-4 keys, 0 to deselect)
			if (keyboard.IsKeyPressed(.Num1)) { mTowerPlacement.SelectedType = .Ballista; Console.WriteLine("[Input] Selected: Ballista"); }
			if (keyboard.IsKeyPressed(.Num2)) { mTowerPlacement.SelectedType = .Cannon; Console.WriteLine("[Input] Selected: Cannon"); }
			if (keyboard.IsKeyPressed(.Num3)) { mTowerPlacement.SelectedType = .Catapult; Console.WriteLine("[Input] Selected: Catapult"); }
			if (keyboard.IsKeyPressed(.Num4)) { mTowerPlacement.SelectedType = .Turret; Console.WriteLine("[Input] Selected: Turret"); }
			if (keyboard.IsKeyPressed(.Num0)) { mTowerPlacement.SelectedType = null; Console.WriteLine("[Input] Deselected tower"); }

			// Tower placement (mouse click on grid)
			mTowerPlacement.Update(mouse, mScene, mGameSub, mGameSub.TowerMgr, mModels, ResourceSystem, mCamera.CameraEntity);

			// Draw debug markers on tower slots and hover
			let renderSub = Context.GetSubsystem<RenderSubsystem>();
			if (renderSub != null)
				mTowerPlacement.DrawDebug(renderSub.DebugDraw, mGameSub);
		}

		// Escape to quit (always available)
		if (keyboard.IsKeyPressed(.Escape))
			Exit();
	}

	// ==================== Shutdown ====================

	protected override void OnShutdown()
	{
		// Clean up UI message subscriptions
		let messaging = Context.GetSubsystem<MessagingSubsystem>();
		let bus = messaging?.Bus;
		mHUD.Shutdown(bus);
		mGameOverUI.Shutdown(bus);

		mModels.Shutdown();
	}

	// ==================== UI Setup ====================

	private void SetupUI()
	{
		let uiSub = Context.GetSubsystem<EngineUISubsystem>();
		if (uiSub?.ScreenView == null)
			return;

		let root = uiSub.ScreenView.Root;
		let messaging = Context.GetSubsystem<MessagingSubsystem>();
		let bus = messaging?.Bus;

		// HUD (top bar - gold, lives, wave)
		mHUD.Setup(root, bus, mGameSub);

		// Tower selection panel (bottom bar - hidden until game starts)
		mTowerPanel.Setup(root, mTowerPlacement, mGameSub);
		mTowerPanel.SetVisible(false);

		// Main menu overlay (shown initially)
		mMainMenu.Setup(root, mGameSub);

		// Game over overlay (hidden until game ends)
		mGameOverUI.Setup(root, bus, mGameSub);
	}
}
