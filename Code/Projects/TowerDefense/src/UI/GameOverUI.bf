namespace TowerDefense;

using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;
using Sedulous.Messaging;

/// Game over overlay shown on win or lose.
class GameOverUI
{
	private Panel mOverlay;
	private Label mResultLabel;
	private Label mStatsLabel;
	private SubscriptionHandle mGameOverSub;

	/// Creates the game over overlay (hidden initially).
	public void Setup(RootView root, MessageBus bus, GameSubsystem gameSub)
	{
		mOverlay = new Panel();
		mOverlay.Background = new ColorDrawable(.(0, 0, 0, 200));
		mOverlay.Visibility = .Gone;

		root.AddView(mOverlay, new LayoutParams()
		{
			Width = LayoutParams.MatchParent,
			Height = LayoutParams.MatchParent
		});

		let layout = new LinearLayout();
		layout.Orientation = .Vertical;
		layout.Spacing = 16;
		mOverlay.AddView(layout, new AbsoluteLayout.LayoutParams()
		{
			X = 0, Y = 200,
			Width = LayoutParams.MatchParent, Height = 300
		});

		// Result label
		mResultLabel = new Label();
		mResultLabel.FontSize = 36;
		mResultLabel.HAlign = .Center;
		layout.AddView(mResultLabel, new LinearLayout.LayoutParams()
		{
			Width = LayoutParams.MatchParent, Height = 50
		});

		// Stats label
		mStatsLabel = new Label();
		mStatsLabel.FontSize = 16;
		mStatsLabel.TextColor = .(200, 200, 200, 255);
		mStatsLabel.HAlign = .Center;
		layout.AddView(mStatsLabel, new LinearLayout.LayoutParams()
		{
			Width = LayoutParams.MatchParent, Height = 24
		});

		// Subscribe to game over message
		if (bus != null)
		{
			mGameOverSub = bus.Subscribe<GameOverMsg>(new (msg) =>
				{
					if (msg.Won)
					{
						mResultLabel.SetText("VICTORY!");
						mResultLabel.TextColor = .(50, 255, 50, 255);
					}
					else
					{
						mResultLabel.SetText("GAME OVER");
						mResultLabel.TextColor = .(255, 50, 50, 255);
					}

					let stats = scope String();
					stats.AppendF("Waves survived: {}  |  Gold: {}  |  Lives: {}",
						gameSub.Waves.CurrentWave, gameSub.Gold, gameSub.Lives);
					mStatsLabel.SetText(stats);

					mOverlay.Visibility = .Visible;
				});
		}
	}

	public void Shutdown(MessageBus bus)
	{
		if (bus != null)
			bus.Unsubscribe(mGameOverSub);
	}
}
