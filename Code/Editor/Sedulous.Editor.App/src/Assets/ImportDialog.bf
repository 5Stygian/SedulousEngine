namespace Sedulous.Editor.App;

using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.UI.Toolkit;
using Sedulous.Core.Mathematics;
using Sedulous.Editor.Core;
using Sedulous.Resources;
using Sedulous.Serialization;

/// Modal dialog for asset import.
/// Shows a preview of items to be imported with checkboxes, output directory,
/// and Import/Cancel buttons.
///
/// Usage:
///   let dialog = new ImportDialog(preview, importer, outputDir, registry, serializer, panel);
///   dialog.Show(ctx);
///   // Dialog owns itself - deleted on close via PopupLayer.
class ImportDialog : Dialog
{
	private ImportPreview mPreview ~ delete _;
	private IAssetImporter mImporter;
	private String mOutputDir = new .() ~ delete _;
	private ResourceRegistry mRegistry;
	private ISerializerProvider mSerializer;
	private AssetBrowserPanel mPanel;

	// Item checkboxes (parallel to mPreview.Items)
	private List<CheckBox> mItemChecks = new .() ~ delete _;

	public this(ImportPreview preview, IAssetImporter importer,
		StringView outputDir, ResourceRegistry registry,
		ISerializerProvider serializer, AssetBrowserPanel panel)
		: base("Import Assets")
	{
		mPreview = preview;
		mImporter = importer;
		mOutputDir.Set(outputDir);
		mRegistry = registry;
		mSerializer = serializer;
		mPanel = panel;

		MaxWidth = 550;
		MaxHeight = 500;

		BuildContent();

		AddButton("Import", .OK);
		AddButton("Cancel", .Cancel);

		OnClosed.Add(new (dialog, result) => {
			if (result == .OK)
				ExecuteImport();
		});
	}

	private void BuildContent()
	{
		let content = new FlexLayout();
		content.Direction = .Vertical;
		content.Spacing = 6;

		// Source file path
		let sourceRow = new FlexLayout();
		sourceRow.Direction = .Horizontal;
		sourceRow.Spacing = 6;

		let sourceLabel = new Label();
		sourceLabel.SetText("Source:");
		sourceLabel.FontSize = 11;
		sourceLabel.TextColor = .(140, 145, 165, 255);
		sourceRow.AddView(sourceLabel, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(50)), Height = .Match });

		let sourcePath = new Label();
		sourcePath.SetText(mPreview.SourcePath);
		sourcePath.FontSize = 11;
		sourcePath.Ellipsis = true;
		sourceRow.AddView(sourcePath, new FlexLayout.LayoutParams() { Height = .Match, Grow = 1 });

		content.AddView(sourceRow, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(18)) });

		// Output directory
		let outputRow = new FlexLayout();
		outputRow.Direction = .Horizontal;
		outputRow.Spacing = 6;

		let outputLabel = new Label();
		outputLabel.SetText("Output:");
		outputLabel.FontSize = 11;
		outputLabel.TextColor = .(140, 145, 165, 255);
		outputRow.AddView(outputLabel, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(50)), Height = .Match });

		let outputPath = new Label();
		outputPath.SetText(mOutputDir);
		outputPath.FontSize = 11;
		outputPath.Ellipsis = true;
		outputRow.AddView(outputPath, new FlexLayout.LayoutParams() { Height = .Match, Grow = 1 });

		content.AddView(outputRow, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(18)) });

		// Separator
		let sep = new Panel();
		sep.Background = new ColorDrawable(.(60, 65, 80, 255));
		content.AddView(sep, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(1)) });

		// Items header
		let headerRow = new FlexLayout();
		headerRow.Direction = .Horizontal;
		headerRow.Spacing = 6;

		let selectAllCheck = new CheckBox("Select All", true);
		selectAllCheck.FontSize = 11;
		selectAllCheck.OnCheckedChanged.Add(new (cb, val) => {
			for (let check in mItemChecks)
				check.IsChecked = val;
		});
		headerRow.AddView(selectAllCheck, new FlexLayout.LayoutParams() { Width = .Wrap, Height = .Match });

		let countLabel = new Label();
		let countText = scope String();
		countText.AppendF("{} items", mPreview.Items.Count);
		countLabel.SetText(countText);
		countLabel.FontSize = 10;
		countLabel.TextColor = .(120, 125, 140, 255);
		countLabel.HAlign = .Right;
		headerRow.AddView(countLabel, new FlexLayout.LayoutParams() { Height = .Match, Grow = 1 });

		content.AddView(headerRow, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(22)) });

		// Item list (scrollable)
		let itemList = new FlexLayout();
		itemList.Direction = .Vertical;
		itemList.Spacing = 2;

		for (let item in mPreview.Items)
		{
			let itemRow = new FlexLayout();
			itemRow.Direction = .Horizontal;
			itemRow.Spacing = 8;

			let check = new CheckBox();
			check.IsChecked = item.Selected;
			mItemChecks.Add(check);
			itemRow.AddView(check, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(20)), Height = .Match });

			// Type label
			let typeLabel = new Label();
			typeLabel.SetText(item.TypeLabel);
			typeLabel.FontSize = 10;
			typeLabel.TextColor = .(140, 160, 200, 255);
			itemRow.AddView(typeLabel, new FlexLayout.LayoutParams() { Width = .Fixed(.Px(90)), Height = .Match });

			// Name + extension
			let nameLabel = new Label();
			let nameText = scope String();
			nameText.AppendF("{}{}", item.Name, item.Extension);
			nameLabel.SetText(nameText);
			nameLabel.FontSize = 11;
			nameLabel.Ellipsis = true;
			itemRow.AddView(nameLabel, new FlexLayout.LayoutParams() { Height = .Match, Grow = 1 });

			itemList.AddView(itemRow, new FlexLayout.LayoutParams() { Width = .Match, Height = .Fixed(.Px(20)) });
		}

		// Wrap item list in a ScrollView for many items
		let scrollView = new ScrollView();
		scrollView.AddView(itemList, new LayoutParams() { Width = .Match, Height = .Wrap });
		content.AddView(scrollView, new FlexLayout.LayoutParams() { Width = .Match, Grow = 1 });

		SetContent(content);
	}

	/// Runs the import with only the checked items.
	private void ExecuteImport()
	{
		// Sync checkbox states to preview items
		for (int i = 0; i < mPreview.Items.Count && i < mItemChecks.Count; i++)
			mPreview.Items[i].Selected = mItemChecks[i].IsChecked;

		// Check if anything is selected
		bool anySelected = false;
		for (let item in mPreview.Items)
		{
			if (item.Selected)
			{
				anySelected = true;
				break;
			}
		}

		if (!anySelected)
			return;

		if (mImporter.Import(mPreview, mOutputDir, mRegistry, mSerializer) case .Ok)
			Console.WriteLine("Imported: {} ({} items selected)", mPreview.SourcePath, mItemChecks.Count);
		else
			Console.WriteLine("Import failed: {}", mPreview.SourcePath);

		mPanel.RefreshContent();
	}
}
