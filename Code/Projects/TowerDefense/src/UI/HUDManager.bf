namespace TowerDefense;

using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;
using Sedulous.Messaging;

/// In-game HUD using DockLayout: top bar (gold/lives/wave/status),
/// bottom bar (tower buttons + info). Added directly to screen RootView.
class HUDManager
{
	private DockLayout mRoot;
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

	/// The root DockLayout. Add to RootView with Match.
	public DockLayout Root => mRoot;

	public void Setup(MessageBus bus, GameSubsystem gameSub, TowerPlacement placement)
	{
		mRoot = new DockLayout();
		mRoot.LastChildFill = false; // don't stretch bottom bar to fill
		mRoot.IsHitTestVisible = false; // let clicks pass through to 3D

		// === Top bar ===
		let topBar = new Panel();
		topBar.Background = new ColorDrawable(.(0, 0, 0, 180));
		topBar.Padding = .(16, 8, 16, 8);

		let topLayout = new FlexLayout();
		topLayout.Direction = .Horizontal;
		topLayout.Spacing = 24;
		topBar.AddView(topLayout, new LayoutParams() { Width = .Match, Height = .Match });

		mGoldLabel = new Label();
		mGoldLabel.FontSize = 16;
		mGoldLabel.TextColor = .(255, 220, 50, 255);
		topLayout.AddView(mGoldLabel, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(120)), Height = .Match });

		mLivesLabel = new Label();
		mLivesLabel.FontSize = 16;
		mLivesLabel.TextColor = .(255, 80, 80, 255);
		topLayout.AddView(mLivesLabel, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(120)), Height = .Match });

		mWaveLabel = new Label();
		mWaveLabel.FontSize = 16;
		mWaveLabel.TextColor = .(150, 180, 255, 255);
		topLayout.AddView(mWaveLabel, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(120)), Height = .Match });

		mStatusLabel = new Label();
		mStatusLabel.FontSize = 14;
		mStatusLabel.TextColor = .(180, 180, 180, 255);
		mStatusLabel.HAlign = .Right;
		topLayout.AddView(mStatusLabel, new FlexLayout.LayoutParams() { Grow = 1, Height = .Match });

		mRoot.AddView(topBar, new DockLayout.LayoutParams(.Top) { Height = .Fixed(.Px(40)) });

		// === Bottom bar ===
		let bottomBar = new Panel();
		bottomBar.Background = new ColorDrawable(.(0, 0, 0, 180));
		bottomBar.Padding = .(16, 8, 16, 8);

		let bottomLayout = new FlexLayout();
		bottomLayout.Direction = .Horizontal;
		bottomLayout.Spacing = 8;
		bottomBar.AddView(bottomLayout, new LayoutParams() { Width = .Match, Height = .Match });

		AddTowerButton(bottomLayout, .Ballista, "1: Ballista", placement);
		AddTowerButton(bottomLayout, .Cannon, "2: Cannon", placement);
		AddTowerButton(bottomLayout, .Catapult, "3: Catapult", placement);
		AddTowerButton(bottomLayout, .Turret, "4: Turret", placement);

		let infoLabel = new Label("Click to place | RMB cancel | Space = wave");
		infoLabel.FontSize = 12;
		infoLabel.TextColor = .(150, 150, 150, 255);
		infoLabel.HAlign = .Right;
		infoLabel.VAlign = .Middle;
		bottomLayout.AddView(infoLabel, new FlexLayout.LayoutParams() { Grow = 1, Height = .Match });

		mRoot.AddView(bottomBar, new DockLayout.LayoutParams(.Bottom) { Height = .Fixed(.Px(50)) });

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

	private void AddTowerButton(FlexLayout layout, TowerType type, StringView label, TowerPlacement placement)
	{
		let stats = TowerStats.Get(type);
		let cost = stats.Levels[0].Cost;
		let text = scope String();
		text.AppendF("{} (${})", label, cost);

		let btn = new Button(text);
		let capturedType = type;
		btn.OnClick.Add(new (b) => { placement.SelectedType = capturedType; });
		layout.AddView(btn, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(130)), Height = .Match });
	}

	private void UpdateLabels(GameSubsystem gs) { UpdateGold(gs); UpdateLives(gs); UpdateWave(gs); }
	private void UpdateGold(GameSubsystem gs) { let s = scope String(); s.AppendF("Gold: {}", gs.Gold); mGoldLabel.SetText(s); }
	private void UpdateLives(GameSubsystem gs) { let s = scope String(); s.AppendF("Lives: {}/{}", gs.Lives, gs.MaxLives); mLivesLabel.SetText(s); }
	private void UpdateWave(GameSubsystem gs) { let s = scope String(); s.AppendF("Wave: {}/{}", gs.Waves.CurrentWave, gs.Waves.TotalWaves); mWaveLabel.SetText(s); }
}
