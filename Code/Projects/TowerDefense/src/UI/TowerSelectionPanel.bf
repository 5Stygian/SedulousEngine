namespace TowerDefense;

using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

/// Bottom panel with tower buy buttons.
class TowerSelectionPanel
{
	private Panel mPanel;
	private TowerPlacement mPlacement;
	private GameSubsystem mGameSub;
	private Label mInfoLabel;

	/// Creates the tower selection panel and adds it to the screen UI root.
	public void Setup(RootView root, TowerPlacement placement, GameSubsystem gameSub)
	{
		mPlacement = placement;
		mGameSub = gameSub;

		mPanel = new Panel();
		mPanel.Background = new ColorDrawable(.(0, 0, 0, 160));
		mPanel.Padding = .(12, 8, 12, 8);

		root.AddView(mPanel, new AbsoluteLayout.LayoutParams()
		{
			X = 0, Y = -80,  // positioned from bottom
			Width = LayoutParams.MatchParent, Height = 80
		});

		let layout = new LinearLayout();
		layout.Orientation = .Horizontal;
		layout.Spacing = 10;
		mPanel.AddView(layout, new LayoutParams()
		{
			Width = LayoutParams.MatchParent,
			Height = LayoutParams.MatchParent
		});

		// Tower buttons
		AddTowerButton(layout, .Ballista, "1: Ballista");
		AddTowerButton(layout, .Cannon, "2: Cannon");
		AddTowerButton(layout, .Catapult, "3: Catapult");
		AddTowerButton(layout, .Turret, "4: Turret");

		// Spacer
		let spacer = new Spacer();
		layout.AddView(spacer, new LinearLayout.LayoutParams() { Width = 20, Height = 1 });

		// Info label
		mInfoLabel = new Label();
		mInfoLabel.FontSize = 13;
		mInfoLabel.TextColor = .(180, 180, 180, 255);
		mInfoLabel.SetText("Select tower, click to place. Right-click to cancel.");
		layout.AddView(mInfoLabel, new LinearLayout.LayoutParams()
		{
			Width = LayoutParams.MatchParent, Height = LayoutParams.MatchParent
		});
	}

	private void AddTowerButton(LinearLayout layout, TowerType type, StringView label)
	{
		let stats = TowerStats.Get(type);
		let cost = stats.Levels[0].Cost;

		let text = scope String();
		text.AppendF("{} (${})", label, cost);

		let btn = new Button();
		btn.SetText(text);

		let capturedType = type;
		btn.OnClick.Add(new (b) =>
			{
				mPlacement.SelectedType = capturedType;
			});

		layout.AddView(btn, new LinearLayout.LayoutParams() { Width = 130, Height = 36 });
	}

	/// Shows or hides the panel.
	public void SetVisible(bool visible)
	{
		if (mPanel != null)
			mPanel.Visibility = visible ? .Visible : .Gone;
	}
}
