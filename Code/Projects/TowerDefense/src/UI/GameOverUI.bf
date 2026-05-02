namespace TowerDefense;

using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;
using Sedulous.Messaging;

/// Game over dialog shown on win or lose. Uses Dialog for auto-centered modal.
class GameOverUI
{
	private SubscriptionHandle mGameOverSub;
	private UIContext mCtx;

	/// Sets up the subscription. Dialog is created when GameOverMsg fires.
	public void Setup(UIContext ctx, MessageBus bus, GameSubsystem gameSub)
	{
		mCtx = ctx;

		if (bus != null)
		{
			mGameOverSub = bus.Subscribe<GameOverMsg>(new (msg) =>
				{
					ShowGameOver(msg.Won, gameSub);
				});
		}
	}

	public void Shutdown(MessageBus bus)
	{
		if (bus != null)
			bus.Unsubscribe(mGameOverSub);
	}

	private void ShowGameOver(bool won, GameSubsystem gameSub)
	{
		let title = won ? "Victory!" : "Game Over";
		let dialog = new Dialog(title);
		dialog.MaxWidth = 400;
		dialog.MaxHeight = 200;

		// Content
		let content = new LinearLayout();
		content.Orientation = .Vertical;
		content.Spacing = 8;

		let resultLabel = new Label();
		resultLabel.FontSize = 18;
		resultLabel.HAlign = .Center;

		if (won)
		{
			resultLabel.SetText("You defended your base!");
			resultLabel.TextColor = .(50, 255, 50, 255);
		}
		else
		{
			resultLabel.SetText("Your base was overrun!");
			resultLabel.TextColor = .(255, 80, 80, 255);
		}
		content.AddView(resultLabel, new LinearLayout.LayoutParams() { Width = LayoutParams.MatchParent, Height = 28 });

		let statsLabel = new Label();
		statsLabel.FontSize = 13;
		statsLabel.TextColor = .(180, 180, 180, 255);
		statsLabel.HAlign = .Center;
		let statsText = scope String();
		statsText.AppendF("Waves: {}  |  Gold: {}  |  Lives: {}",
			gameSub.Waves.CurrentWave, gameSub.Gold, gameSub.Lives);
		statsLabel.SetText(statsText);
		content.AddView(statsLabel, new LinearLayout.LayoutParams() { Width = LayoutParams.MatchParent, Height = 20 });

		dialog.SetContent(content);
		dialog.AddButton("OK", .OK);

		if (mCtx != null)
			dialog.Show(mCtx);
	}
}
