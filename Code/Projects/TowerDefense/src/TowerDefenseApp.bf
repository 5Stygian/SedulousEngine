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
using Sedulous.Engine.Audio;
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
	private MainMenuUI mMainMenu = new .() ~ delete _;
	private GameOverUI mGameOverUI = new .() ~ delete _;
	private PauseUI mPauseUI = new .() ~ delete _;

	// Audio
	private GameAudio mGameAudio = new .() ~ delete _;

	// Particles
	private ParticleEffects mParticleEffects = new .() ~ delete _;

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
		let pipeline = renderSub.GetPipeline(mScene);
		if (pipeline?.LightBuffer != null)
			pipeline.LightBuffer.AmbientColor = .(0.05f, 0.05f, 0.08f);

		// Set up UI
		SetupUI();

		// Set up audio
		let audioSub = Context.GetSubsystem<AudioSubsystem>();
		let messaging = Context.GetSubsystem<MessagingSubsystem>();
		if (audioSub != null)
			mGameAudio.Initialize(audioSub, messaging?.Bus);

		// Set up particle effects
		let assetDir2 = scope String();
		GetAssetPath("", assetDir2);
		mParticleEffects.Initialize(mScene, messaging?.Bus, ResourceSystem, assetDir2);

		Console.WriteLine("=== Tower Defense Ready ===");
	}

	// ==================== Update ====================

	protected override void OnUpdate(float deltaTime)
	{
		if (mScene == null)
			return;

		// Clean up expired particle effects
		mParticleEffects.Update(deltaTime);

		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		// Camera controls (always available except menu)
		if (mGameSub.Phase != .MainMenu)
		{
			mCamera.Update(deltaTime, keyboard, mouse);
			mCamera.ApplyToScene(mScene);
		}

		// Pause toggle (P or Escape during gameplay)
		if (keyboard.IsKeyPressed(.P) || keyboard.IsKeyPressed(.Escape))
		{
			if (mGameSub.IsGameplayPhase)
			{
				mGameSub.PauseGame();
				let uiSub = Context.GetSubsystem<EngineUISubsystem>();
				if (uiSub?.ScreenView != null)
					mPauseUI.Show();
			}
			else if (mGameSub.Phase == .Paused)
			{
				mGameSub.ResumeGame();
				mPauseUI.Hide();
			}
		}

		// Gameplay input (active gameplay phases only)
		if (mGameSub.IsGameplayPhase)
		{
			// Space to start next wave
			if (keyboard.IsKeyPressed(.Space) && (mGameSub.Phase == .WaitingToStart || mGameSub.Phase == .WavePaused))
			{
				StartWave();
			}

			// Tower selection (1-4 keys, 0 to deselect)
			if (keyboard.IsKeyPressed(.Num1)) { mTowerPlacement.SelectedType = .Ballista; }
			if (keyboard.IsKeyPressed(.Num2)) { mTowerPlacement.SelectedType = .Cannon; }
			if (keyboard.IsKeyPressed(.Num3)) { mTowerPlacement.SelectedType = .Catapult; }
			if (keyboard.IsKeyPressed(.Num4)) { mTowerPlacement.SelectedType = .Turret; }
			if (keyboard.IsKeyPressed(.Num0)) { mTowerPlacement.SelectedType = null; }

			// Tower placement (mouse click on grid)
			mTowerPlacement.Update(mouse, mScene, mGameSub, mGameSub.TowerMgr, mModels, ResourceSystem, mCamera.CameraEntity);

			// Draw debug markers on tower slots and hover
			let renderSub = Context.GetSubsystem<RenderSubsystem>();
			if (renderSub != null)
			{
				mTowerPlacement.DrawDebug(renderSub.DebugDraw, mGameSub);

				// Health bars — billboard using camera vectors
			let offsetY = mCamera.Zoom * Math.Cos(mCamera.ViewAngle);
			let offsetZ = mCamera.Zoom * Math.Sin(mCamera.ViewAngle);
			let camPos = mCamera.LookTarget + Vector3(0, offsetY, offsetZ);
			let camFwd = Vector3.Normalize(mCamera.LookTarget - camPos);
			let camRight = Vector3.Normalize(Vector3.Cross(camFwd, .(0, 1, 0)));
			let camUp = Vector3.Cross(camRight, camFwd);
			mGameSub.EnemyMgr?.DrawHealthBars(renderSub.DebugDraw, camRight, camUp);
			}
		}
	}

	// ==================== Shutdown ====================

	protected override void OnShutdown()
	{
		// Clean up effects and audio
		mParticleEffects.Shutdown();
		mGameAudio.Shutdown();

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

		// Resolve preview image directory.
		let previewDir = scope String();
		GetAssetPath("samples/models/kenney_tower-defense-kit/Previews", previewDir);

		// HUD (DockLayout with top and bottom bars, fills screen)
		mHUD.Setup(bus, mGameSub, mTowerPlacement, previewDir);
		mHUD.StartWaveCallback = new () => StartWave();
		mHUD.SetSpeedCallback = new (speed) => mGameSub.SetGameSpeed(speed);
		root.AddView(mHUD.Root, new LayoutParams() { Width = .Match, Height = .Match });

		// Game over / victory overlay (subscribes to GameOverMsg)
		mGameOverUI.Setup(root, bus,
			new () => RestartGame(),
			new () => { ReturnToMainMenu(); }
		);

		// Pause overlay
		mPauseUI.Setup(root,
			new () => { mGameSub.ResumeGame(); mPauseUI.Hide(); },
			new () => { mPauseUI.Hide(); ReturnToMainMenu(); }
		);

		// Main menu (full-screen overlay, shown on top of everything)
		mMainMenu.Setup(root, new () => StartGame());
		mMainMenu.Show();
	}

	private void StartGame()
	{
		mMainMenu.Hide();
		mGameSub.SetPhase(.WaitingToStart);
		Console.WriteLine("[Game] Ready - place towers, then press Space or click Start Wave");
	}

	private void RestartGame()
	{
		// Reset game state
		mGameSub.ResetGame();
		mGameSub.SetPhase(.WaitingToStart);
		Console.WriteLine("[Game] Restarted");
	}

	private void ReturnToMainMenu()
	{
		mGameSub.SetPhase(.MainMenu);
		mGameSub.ResetGame();

		let uiSub = Context.GetSubsystem<EngineUISubsystem>();
		if (uiSub?.ScreenView != null)
			mMainMenu.Show();
	}

	private void StartWave()
	{
		if (!mGameSub.Waves.IsWaveActive)
		{
			mGameSub.Waves.StartNextWave();
			mGameSub.SetPhase(.WaveInProgress);
		}
	}
}
