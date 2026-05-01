namespace TowerDefense;

using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

/// Main menu overlay shown at game start.
class MainMenuUI
{
	private Panel mOverlay;

	/// Creates the main menu overlay and adds it to the screen UI root.
	public void Setup(RootView root, GameSubsystem gameSub)
	{
		mOverlay = new Panel();
		mOverlay.Background = new ColorDrawable(.(0, 0, 0, 180));

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

		// Title
		let title = new Label();
		title.SetText("Tower Defense");
		title.FontSize = 32;
		title.TextColor = .(255, 220, 50, 255);
		title.HAlign = .Center;
		layout.AddView(title, new LinearLayout.LayoutParams()
		{
			Width = LayoutParams.MatchParent, Height = 50
		});

		// Subtitle
		let subtitle = new Label();
		subtitle.SetText("Defend your base against waves of enemies!");
		subtitle.FontSize = 16;
		subtitle.TextColor = .(200, 200, 200, 255);
		subtitle.HAlign = .Center;
		layout.AddView(subtitle, new LinearLayout.LayoutParams()
		{
			Width = LayoutParams.MatchParent, Height = 24
		});

		// Start button
		let startBtn = new Button();
		startBtn.SetText("Start Game (Enter)");
		startBtn.OnClick.Add(new (b) =>
			{
				gameSub.SetPhase(.Playing);
				Hide();
			});

		layout.AddView(startBtn, new LinearLayout.LayoutParams()
		{
			Width = 250, Height = 40
		});

		// Controls hint
		let controls = new Label();
		controls.SetText("1-4: Select tower  |  Click: Place  |  Space: Start wave  |  RMB: Cancel");
		controls.FontSize = 12;
		controls.TextColor = .(150, 150, 150, 255);
		controls.HAlign = .Center;
		layout.AddView(controls, new LinearLayout.LayoutParams()
		{
			Width = LayoutParams.MatchParent, Height = 20
		});
	}

	public void Show()
	{
		if (mOverlay != null)
			mOverlay.Visibility = .Visible;
	}

	public void Hide()
	{
		if (mOverlay != null)
			mOverlay.Visibility = .Gone;
	}
}
