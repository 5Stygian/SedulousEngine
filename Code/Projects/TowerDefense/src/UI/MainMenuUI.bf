namespace TowerDefense;

using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

/// Main menu shown at game start. Uses Dialog for auto-centered modal.
class MainMenuUI
{
	private Dialog mDialog;

	/// Shows the main menu dialog.
	public void Show(UIContext ctx, GameSubsystem gameSub, delegate void() onStart)
	{
		mDialog = new Dialog("Tower Defense");
		mDialog.MaxWidth = 500;
		mDialog.MaxHeight = 250;

		// Content
		let content = new LinearLayout();
		content.Orientation = .Vertical;
		content.Spacing = 12;

		let subtitle = new Label();
		subtitle.SetText("Defend your base against waves of enemies!");
		subtitle.FontSize = 14;
		subtitle.TextColor = .(200, 200, 200, 255);
		subtitle.HAlign = .Center;
		content.AddView(subtitle, new LinearLayout.LayoutParams() { Width = LayoutParams.MatchParent, Height = 24 });

		let controls = new Label();
		controls.SetText("1-4: Select tower | Click: Place | Space: Wave | RMB: Cancel");
		controls.FontSize = 11;
		controls.TextColor = .(140, 140, 140, 255);
		controls.HAlign = .Center;
		content.AddView(controls, new LinearLayout.LayoutParams() { Width = LayoutParams.MatchParent, Height = 18 });

		mDialog.SetContent(content);

		// Start button
		let startBtn = mDialog.AddButton("Start Game", .OK);

		let capturedOnStart = onStart;
		mDialog.OnClosed.Add(new (dlg, result) =>
			{
				if (result == .OK && capturedOnStart != null)
					capturedOnStart();
			});

		mDialog.Show(ctx);
	}
}
