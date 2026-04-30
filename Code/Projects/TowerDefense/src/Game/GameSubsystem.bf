namespace TowerDefense;

using System;
using Sedulous.Runtime;
using Sedulous.Engine.Core;
using Sedulous.Messaging;
using Sedulous.Messaging.Runtime;
using Sedulous.Engine;
using Sedulous.Resources;

/// Central game subsystem. Manages game state (gold, lives, phase) and
/// injects all gameplay ComponentManagers into scenes. Owns MapSystem
/// and WaveSystem as plain objects.
class GameSubsystem : Subsystem, ISceneAware
{
	public override int32 UpdateOrder => -200;

	// Game state
	private int32 mGold = 250;
	private int32 mLives = 20;
	private int32 mMaxLives = 20;
	private int32 mCurrentWave;
	private int32 mTotalWaves = 10;
	private GamePhase mPhase = .MainMenu;

	// Owned systems
	private MapSystem mMapSystem = new .() ~ delete _;
	private WaveSystem mWaveSystem = new .() ~ delete _;

	// Injected references (set by TowerDefenseApp before startup)
	public ModelRegistry Models;
	public ResourceSystem Resources;

	// Component managers (injected into scene, held for cross-system access)
	private EnemyComponentManager mEnemyMgr;
	private TowerComponentManager mTowerMgr;
	private ProjectileComponentManager mProjectileMgr;

	public TowerComponentManager TowerMgr => mTowerMgr;

	// Message bus (resolved in OnReady)
	private MessageBus mBus;
	private SubscriptionHandle mEnemyKilledSub;
	private SubscriptionHandle mEnemyReachedEndSub;
	private SubscriptionHandle mWaveCompletedSub;

	// --- Public API ---

	public int32 Gold => mGold;
	public int32 Lives => mLives;
	public int32 MaxLives => mMaxLives;
	public int32 CurrentWave => mWaveSystem.CurrentWave;
	public int32 TotalWaves => mWaveSystem.TotalWaves;
	public GamePhase Phase => mPhase;
	public MapSystem Map => mMapSystem;
	public WaveSystem Waves => mWaveSystem;

	/// Attempts to spend gold. Returns true if sufficient, false otherwise.
	public bool SpendGold(int32 amount)
	{
		if (mGold < amount)
			return false;

		mGold -= amount;
		PublishResourceChanged(-amount);
		return true;
	}

	/// Adds gold and publishes resource change.
	public void AddGold(int32 amount)
	{
		mGold += amount;
		PublishResourceChanged(amount);
	}

	/// Sets the game phase and publishes change message.
	public void SetPhase(GamePhase newPhase)
	{
		if (mPhase == newPhase)
			return;

		let oldPhase = mPhase;
		mPhase = newPhase;

		if (mBus != null)
		{
			GamePhaseChangedMsg msg = .() { OldPhase = oldPhase, NewPhase = newPhase };
			mBus.Publish<GamePhaseChangedMsg>(ref msg);
		}
	}

	/// Resets game state for a new game.
	public void ResetGame()
	{
		mGold = 250;
		mLives = 20;
		mCurrentWave = 0;
	}

	// --- Lifecycle ---

	protected override void OnReady()
	{
		// Get message bus from MessagingSubsystem
		let messaging = Context.GetSubsystem<MessagingSubsystem>();
		if (messaging != null)
		{
			mBus = messaging.Bus;

			// Subscribe to game events
			mEnemyKilledSub = mBus.Subscribe<EnemyKilledMsg>(new (msg) =>
				{
					AddGold(msg.Reward);
					Console.WriteLine("[Game] Enemy killed, +{} gold (total: {})", msg.Reward, mGold);
				});

			mEnemyReachedEndSub = mBus.Subscribe<EnemyReachedEndMsg>(new (msg) =>
				{
					if (mPhase != .Playing)
						return; // already game over, ignore further arrivals

					mLives = Math.Max(0, mLives - msg.LivesLost);
					Console.WriteLine("[Game] Enemy reached end, -{} lives (remaining: {})", msg.LivesLost, mLives);
					if (mLives <= 0)
					{
						SetPhase(.GameOver);
						Console.WriteLine("[Game] GAME OVER - lives depleted");
						GameOverMsg gameOverMsg = .() { Won = false };
						mBus.Publish<GameOverMsg>(ref gameOverMsg);
					}
				});

			mWaveCompletedSub = mBus.Subscribe<WaveCompletedMsg>(new (msg) =>
				{
					mCurrentWave = msg.WaveNumber;
					if (mCurrentWave >= mTotalWaves)
					{
						SetPhase(.Victory);
						GameOverMsg gameOverMsg = .() { Won = true };
						mBus.Publish<GameOverMsg>(ref gameOverMsg);
					}
				});
		}
	}

	public override void Update(float deltaTime)
	{
		// Update wave spawning
		if (mPhase == .Playing)
			mWaveSystem.Update(deltaTime);
	}

	protected override void OnPrepareShutdown()
	{
		mWaveSystem.Shutdown();

		if (mBus != null)
		{
			mBus.Unsubscribe(mEnemyKilledSub);
			mBus.Unsubscribe(mEnemyReachedEndSub);
			mBus.Unsubscribe(mWaveCompletedSub);
		}
	}

	// --- ISceneAware ---

	public void OnSceneCreated(Scene scene)
	{
		// Inject enemy component manager
		mEnemyMgr = new EnemyComponentManager();
		mEnemyMgr.Bus = mBus;
		mEnemyMgr.Models = Models;
		mEnemyMgr.Resources = Resources;
		scene.AddModule(mEnemyMgr);

		// Inject projectile component manager
		mProjectileMgr = new ProjectileComponentManager();
		mProjectileMgr.Bus = mBus;
		mProjectileMgr.EnemyMgr = mEnemyMgr;
		mProjectileMgr.Models = Models;
		mProjectileMgr.Resources = Resources;
		scene.AddModule(mProjectileMgr);

		// Inject tower component manager
		mTowerMgr = new TowerComponentManager();
		mTowerMgr.Bus = mBus;
		mTowerMgr.EnemyMgr = mEnemyMgr;
		mTowerMgr.ProjectileMgr = mProjectileMgr;
		scene.AddModule(mTowerMgr);

		// Initialize wave system with enemy manager
		if (mBus != null)
			mWaveSystem.Initialize(mBus, mEnemyMgr);
	}

	public void OnSceneReady(Scene scene)
	{
		// Update enemy waypoints now that the map may have been built
		UpdateWaypoints();
	}

	/// Call after BuildMap to update enemy waypoints.
	public void UpdateWaypoints()
	{
		if (mEnemyMgr != null)
			mEnemyMgr.Waypoints = mMapSystem.GetWaypoints();
	}
	public void OnSceneDestroyed(Scene scene) { }

	// --- Internal ---

	private void PublishResourceChanged(int32 delta)
	{
		if (mBus != null)
		{
			ResourceChangedMsg msg = .() { NewAmount = mGold, Delta = delta };
			mBus.Publish<ResourceChangedMsg>(ref msg);
		}
	}
}
