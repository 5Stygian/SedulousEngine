namespace TowerDefense;

using System;
using Sedulous.LegacyUI;
using Sedulous.Core.Mathematics;
using Sedulous.Messaging;

/// In-game HUD using DockView: top bar (gold/lives/wave/status),
/// bottom bar (tower buttons + info). Added directly to screen RootView.
class HUDManager
{
	private DockView mRoot;
	private Label mGoldLabel;
	private Label mLivesLabel;
	private Label mWaveLabel;
	private Label mStatusLabel;

	// Message subscriptions
	private SubscriptionHandle mResourceSub;
	private SubscriptionHandle mEnemyReachedSub;
	private SubscriptionHandle mWaveStartedSub;
	private SubscriptionHandle mWaveCompletedSub;
	private SubscriptionHandle mGameOverSub;
	private SubscriptionHandle mPhaseChangedSub;

	/// The root DockView. Add to RootView with MatchParent.
	public DockView Root => mRoot;

	public void Setup(MessageBus bus, GameSubsystem gameSub, TowerPlacement placement)
	{
		mRoot = new DockView();
		mRoot.LastChildFill = false; // don't stretch bottom bar to fill
		mRoot.IsHitTestVisible = false; // let clicks pass through to 3D

		// === Top bar ===
		let topBar = new Panel();
		topBar.Background = new ColorDrawable(.(0, 0, 0, 180));
		topBar.Padding = .(16, 8, 16, 8);

		let topLayout = new LinearLayout();
		topLayout.Orientation = .Horizontal;
		topLayout.Spacing = 24;
		topBar.AddView(topLayout, new LayoutParams() { Width = LayoutParams.MatchParent, Height = LayoutParams.MatchParent });

		mGoldLabel = new Label();
		mGoldLabel.FontSize = 16;
		mGoldLabel.TextColor = .(255, 220, 50, 255);
		topLayout.AddView(mGoldLabel, new LinearLayout.LayoutParams() { Width = 120, Height = LayoutParams.MatchParent });

		mLivesLabel = new Label();
		mLivesLabel.FontSize = 16;
		mLivesLabel.TextColor = .(255, 80, 80, 255);
		topLayout.AddView(mLivesLabel, new LinearLayout.LayoutParams() { Width = 120, Height = LayoutParams.MatchParent });

		mWaveLabel = new Label();
		mWaveLabel.FontSize = 16;
		mWaveLabel.TextColor = .(150, 180, 255, 255);
		topLayout.AddView(mWaveLabel, new LinearLayout.LayoutParams() { Width = 120, Height = LayoutParams.MatchParent });

		mStatusLabel = new Label();
		mStatusLabel.FontSize = 14;
		mStatusLabel.TextColor = .(180, 180, 180, 255);
		mStatusLabel.HAlign = .Right;
		topLayout.AddView(mStatusLabel, new LinearLayout.LayoutParams() { Width = 0, Height = LayoutParams.MatchParent, Weight = 1 });

		mRoot.AddView(topBar, new DockView.LayoutParams(.Top) { Height = 40 });

		// === Bottom bar ===
		let bottomBar = new Panel();
		bottomBar.Background = new ColorDrawable(.(0, 0, 0, 180));
		bottomBar.Padding = .(16, 8, 16, 8);

		let bottomLayout = new LinearLayout();
		bottomLayout.Orientation = .Horizontal;
		bottomLayout.Spacing = 8;
		bottomBar.AddView(bottomLayout, new LayoutParams() { Width = LayoutParams.MatchParent, Height = LayoutParams.MatchParent });

		AddTowerButton(bottomLayout, .Ballista, "1: Ballista", placement);
		AddTowerButton(bottomLayout, .Cannon, "2: Cannon", placement);
		AddTowerButton(bottomLayout, .Catapult, "3: Catapult", placement);
		AddTowerButton(bottomLayout, .Turret, "4: Turret", placement);

		let infoLabel = new Label();
		infoLabel.FontSize = 12;
		infoLabel.TextColor = .(150, 150, 150, 255);
		infoLabel.SetText("Click to place | RMB cancel | Space = wave");
		infoLabel.HAlign = .Right;
		infoLabel.VAlign = .Middle;
		bottomLayout.AddView(infoLabel, new LinearLayout.LayoutParams() { Width = 0, Height = LayoutParams.MatchParent, Weight = 1 });

		mRoot.AddView(bottomBar, new DockView.LayoutParams(.Bottom) { Height = 50 });

		// Initial values
		UpdateLabels(gameSub);
		mStatusLabel.SetText("Press Enter to start");

		// Message subscriptions for live updates
		if (bus != null)
		{
			mResourceSub = bus.Subscribe<ResourceChangedMsg>(new (msg) => { UpdateGold(gameSub); });
			mEnemyReachedSub = bus.Subscribe<EnemyReachedEndMsg>(new (msg) => { UpdateLives(gameSub); });
			mWaveStartedSub = bus.Subscribe<WaveStartedMsg>(new (msg) => { UpdateWave(gameSub); mStatusLabel.SetText("Wave in progress..."); });
			mWaveCompletedSub = bus.Subscribe<WaveCompletedMsg>(new (msg) => { UpdateWave(gameSub); mStatusLabel.SetText("Press Space for next wave"); });
			mGameOverSub = bus.Subscribe<GameOverMsg>(new (msg) => { mStatusLabel.SetText(msg.Won ? "VICTORY!" : "GAME OVER"); });
			mPhaseChangedSub = bus.Subscribe<GamePhaseChangedMsg>(new (msg) =>
				{
					if (msg.NewPhase == .Playing) { mStatusLabel.SetText("Place towers, then Space"); UpdateLabels(gameSub); }
				});
		}
	}

	public void Shutdown(MessageBus bus)
	{
		if (bus != null)
		{
			bus.Unsubscribe(mResourceSub);
			bus.Unsubscribe(mEnemyReachedSub);
			bus.Unsubscribe(mWaveStartedSub);
			bus.Unsubscribe(mWaveCompletedSub);
			bus.Unsubscribe(mGameOverSub);
			bus.Unsubscribe(mPhaseChangedSub);
		}
	}

	private void AddTowerButton(LinearLayout layout, TowerType type, StringView label, TowerPlacement placement)
	{
		let stats = TowerStats.Get(type);
		let cost = stats.Levels[0].Cost;
		let text = scope String();
		text.AppendF("{} (${})", label, cost);

		let btn = new Button();
		btn.SetText(text);
		let capturedType = type;
		btn.OnClick.Add(new (b) => { placement.SelectedType = capturedType; });
		layout.AddView(btn, new LinearLayout.LayoutParams() { Width = 130, Height = LayoutParams.MatchParent });
	}

	private void UpdateLabels(GameSubsystem gs) { UpdateGold(gs); UpdateLives(gs); UpdateWave(gs); }
	private void UpdateGold(GameSubsystem gs) { let s = scope String(); s.AppendF("Gold: {}", gs.Gold); mGoldLabel.SetText(s); }
	private void UpdateLives(GameSubsystem gs) { let s = scope String(); s.AppendF("Lives: {}/{}", gs.Lives, gs.MaxLives); mLivesLabel.SetText(s); }
	private void UpdateWave(GameSubsystem gs) { let s = scope String(); s.AppendF("Wave: {}/{}", gs.Waves.CurrentWave, gs.Waves.TotalWaves); mWaveLabel.SetText(s); }
}
