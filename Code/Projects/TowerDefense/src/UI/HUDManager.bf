namespace TowerDefense;

using System;
using Sedulous.UI;
using Sedulous.Messaging;
using Sedulous.Core.Mathematics;

/// Manages the in-game HUD: gold, lives, wave info, and controls hint.
class HUDManager
{
	private Label mGoldLabel;
	private Label mLivesLabel;
	private Label mWaveLabel;
	private Label mStatusLabel;
	private Panel mHudPanel;

	// Message subscriptions
	private SubscriptionHandle mResourceSub;
	private SubscriptionHandle mEnemyReachedSub;
	private SubscriptionHandle mWaveStartedSub;
	private SubscriptionHandle mWaveCompletedSub;
	private SubscriptionHandle mGameOverSub;
	private SubscriptionHandle mPhaseChangedSub;

	/// Creates the HUD and adds it to the screen UI root.
	public void Setup(RootView root, MessageBus bus, GameSubsystem gameSub)
	{
		// Top HUD bar
		mHudPanel = new Panel();
		mHudPanel.Background = new ColorDrawable(.(0, 0, 0, 160));
		mHudPanel.Padding = .(12, 6, 12, 6);

		root.AddView(mHudPanel, new AbsoluteLayout.LayoutParams()
		{
			X = 0, Y = 0,
			Width = LayoutParams.MatchParent, Height = 60
		});

		let layout = new LinearLayout();
		layout.Orientation = .Horizontal;
		layout.Spacing = 20;
		mHudPanel.AddView(layout, new LayoutParams()
		{
			Width = LayoutParams.MatchParent,
			Height = LayoutParams.MatchParent
		});

		// Gold label
		mGoldLabel = new Label();
		mGoldLabel.FontSize = 16;
		mGoldLabel.TextColor = .(255, 220, 50, 255);
		layout.AddView(mGoldLabel, new LinearLayout.LayoutParams() { Width = 150, Height = LayoutParams.MatchParent });

		// Lives label
		mLivesLabel = new Label();
		mLivesLabel.FontSize = 16;
		mLivesLabel.TextColor = .(255, 80, 80, 255);
		layout.AddView(mLivesLabel, new LinearLayout.LayoutParams() { Width = 150, Height = LayoutParams.MatchParent });

		// Wave label
		mWaveLabel = new Label();
		mWaveLabel.FontSize = 16;
		mWaveLabel.TextColor = .(200, 200, 255, 255);
		layout.AddView(mWaveLabel, new LinearLayout.LayoutParams() { Width = 200, Height = LayoutParams.MatchParent });

		// Status label (right side)
		mStatusLabel = new Label();
		mStatusLabel.FontSize = 14;
		mStatusLabel.TextColor = .(180, 180, 180, 255);
		layout.AddView(mStatusLabel, new LinearLayout.LayoutParams()
		{
			Width = LayoutParams.MatchParent, Height = LayoutParams.MatchParent
		});

		// Set initial values
		UpdateLabels(gameSub);
		mStatusLabel.SetText("Press Enter to start");

		// Subscribe to game messages for live updates
		if (bus != null)
		{
			mResourceSub = bus.Subscribe<ResourceChangedMsg>(new (msg) =>
				{
					UpdateGold(gameSub);
				});

			mEnemyReachedSub = bus.Subscribe<EnemyReachedEndMsg>(new (msg) =>
				{
					UpdateLives(gameSub);
				});

			mWaveStartedSub = bus.Subscribe<WaveStartedMsg>(new (msg) =>
				{
					UpdateWave(gameSub);
					mStatusLabel.SetText("Wave in progress...");
				});

			mWaveCompletedSub = bus.Subscribe<WaveCompletedMsg>(new (msg) =>
				{
					UpdateWave(gameSub);
					mStatusLabel.SetText("Press Space for next wave");
				});

			mGameOverSub = bus.Subscribe<GameOverMsg>(new (msg) =>
				{
					if (msg.Won)
						mStatusLabel.SetText("VICTORY!");
					else
						mStatusLabel.SetText("GAME OVER");
				});

			mPhaseChangedSub = bus.Subscribe<GamePhaseChangedMsg>(new (msg) =>
				{
					if (msg.NewPhase == .Playing)
					{
						mStatusLabel.SetText("Place towers (1-4), then Space");
						UpdateLabels(gameSub);
					}
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

	private void UpdateLabels(GameSubsystem gameSub)
	{
		UpdateGold(gameSub);
		UpdateLives(gameSub);
		UpdateWave(gameSub);
	}

	private void UpdateGold(GameSubsystem gameSub)
	{
		let text = scope String();
		text.AppendF("Gold: {}", gameSub.Gold);
		mGoldLabel.SetText(text);
	}

	private void UpdateLives(GameSubsystem gameSub)
	{
		let text = scope String();
		text.AppendF("Lives: {}/{}", gameSub.Lives, gameSub.MaxLives);
		mLivesLabel.SetText(text);
	}

	private void UpdateWave(GameSubsystem gameSub)
	{
		let text = scope String();
		text.AppendF("Wave: {}/{}", gameSub.Waves.CurrentWave, gameSub.Waves.TotalWaves);
		mWaveLabel.SetText(text);
	}
}
