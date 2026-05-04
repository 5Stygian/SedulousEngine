namespace Sedulous.Editor.App;

using System;
using System.Collections;
using Sedulous.LegacyUI;
using Sedulous.LegacyUI.Toolkit;
using Sedulous.Core.Mathematics;
using Sedulous.Editor.Core;
using Sedulous.Resources;

using internal Sedulous.LegacyUI;

/// Modal dialog for selecting a resource from mounted registries.
/// Shows registry tree (left) + content list/grid (right) with only
/// registered items visible. Optional extension filter.
///
/// Usage:
///   let picker = new AssetPickerDialog(editorContext, ".mesh",
///       new (path, id) => { /* use selected asset */ });
///   picker.Show(ctx);
class AssetPickerDialog : Dialog
{
	private EditorContext mEditorContext;
	private delegate void(StringView, Guid) mOnSelected ~ delete _;
	private Button mSelectBtn;

	// Adapters (owned by this dialog, not by views - views are deleted by Dialog)
	private RegistryTreeAdapter mTreeAdapter ~ delete _;
	private AssetContentAdapter mListAdapter ~ delete _;
	private AssetContentAdapter mGridAdapter ~ delete _;

	// Content views (for selection tracking)
	private ListView mContentList;
	private GridContentView mContentGrid;
	private bool mGridMode;

	public this(EditorContext editorContext, StringView extensionFilter,
		delegate void(StringView protocolPath, Guid id) onSelected)
		: base("Select Asset")
	{
		mEditorContext = editorContext;
		mOnSelected = onSelected;

		MaxWidth = 600;
		MaxHeight = 500;

		BuildContent(extensionFilter);

		mSelectBtn = AddButton("Select", .OK);
		AddButton("Cancel", .Cancel);

		OnClosed.Add(new (dialog, result) => {
			if (result == .OK)
				ConfirmSelection();
		});
	}

	private void BuildContent(StringView extensionFilter)
	{
		let resourceSystem = mEditorContext.ResourceSystem;

		// Create adapters
		mTreeAdapter = new RegistryTreeAdapter();
		mListAdapter = new AssetContentAdapter();
		mListAdapter.ViewMode = .List;
		mListAdapter.RegistryOnly = true;
		mListAdapter.SetExtensionFilter(extensionFilter);

		mGridAdapter = new AssetContentAdapter();
		mGridAdapter.ViewMode = .Grid;
		mGridAdapter.RegistryOnly = true;
		mGridAdapter.SetExtensionFilter(extensionFilter);

		// Populate tree from registries
		let registries = scope List<IResourceRegistry>();
		resourceSystem.GetRegistries(registries);
		mTreeAdapter.SetRegistries(registries);

		// === Layout ===
		let split = new SplitView(.Horizontal);
		split.SplitRatio = 0.3f;

		// Left: registry tree
		let treeView = new TreeView();
		treeView.ItemHeight = 22;
		treeView.IndentWidth = 16;
		treeView.SetAdapter(mTreeAdapter);

		// Right: nav bar + content
		let rightPane = new LinearLayout();
		rightPane.Orientation = .Vertical;

		// Nav bar: breadcrumb + view toggle
		let navBar = new LinearLayout();
		navBar.Orientation = .Horizontal;
		navBar.Padding = .(0, 0, 4, 0);

		let breadcrumb = new BreadcrumbBar();
		navBar.AddView(breadcrumb, new LinearLayout.LayoutParams() { Width = 0, Height = Sedulous.LegacyUI.LayoutParams.MatchParent, Weight = 1 });

		let listBtn = new ToggleButton();
		listBtn.SetText("List");
		listBtn.IsChecked = true;
		let gridBtn = new ToggleButton();
		gridBtn.SetText("Grid");
		navBar.AddView(listBtn, new LinearLayout.LayoutParams() { Height = Sedulous.LegacyUI.LayoutParams.MatchParent });
		navBar.AddView(gridBtn, new LinearLayout.LayoutParams() { Height = Sedulous.LegacyUI.LayoutParams.MatchParent });

		rightPane.AddView(navBar, new LinearLayout.LayoutParams() {
			Width = Sedulous.LegacyUI.LayoutParams.MatchParent, Height = Sedulous.LegacyUI.LayoutParams.WrapContent
		});

		// Separator
		let sep = new Panel();
		sep.Background = new ColorDrawable(.(50, 55, 65, 255));
		rightPane.AddView(sep, new LinearLayout.LayoutParams() {
			Width = Sedulous.LegacyUI.LayoutParams.MatchParent, Height = 1
		});

		// Content container
		let contentContainer = new Panel();
		rightPane.AddView(contentContainer, new LinearLayout.LayoutParams() {
			Width = Sedulous.LegacyUI.LayoutParams.MatchParent, Height = 0, Weight = 1
		});

		// List view (default)
		mContentList = new ListView();
		mContentList.ItemHeight = 24;
		mContentList.Adapter = mListAdapter;
		mContentList.Selection.Mode = .Single;
		mListAdapter.OwnerListView = mContentList;
		contentContainer.AddView(mContentList, new LayoutParams() {
			Width = Sedulous.LegacyUI.LayoutParams.MatchParent, Height = Sedulous.LegacyUI.LayoutParams.MatchParent
		});

		// Grid view (hidden)
		mContentGrid = new GridContentView();
		mContentGrid.CellWidth = 80;
		mContentGrid.CellHeight = 96;
		mContentGrid.Adapter = mGridAdapter;
		mContentGrid.Selection.Mode = .Single;
		mContentGrid.Visibility = .Gone;
		mGridAdapter.OwnerGridView = mContentGrid;
		contentContainer.AddView(mContentGrid, new LayoutParams() {
			Width = Sedulous.LegacyUI.LayoutParams.MatchParent, Height = Sedulous.LegacyUI.LayoutParams.MatchParent
		});

		split.SetPanes(treeView, rightPane);

		// === Wire events ===

		// Tree click -> navigate
		treeView.OnItemClick.Add(new (clickInfo) => {
			mTreeAdapter.SelectNode(clickInfo.NodeId);
		});

		mTreeAdapter.OnFolderSelected.Add(new (registry, relativePath) => {
			mListAdapter.SetFolder(registry, relativePath);
			mGridAdapter.SetFolder(registry, relativePath);
			breadcrumb.SetPath(registry.Name, relativePath);
		});

		// List double-click -> navigate folder or select asset
		mContentList.OnItemClicked.Add(new (position, clickCount, x, y) => {
			if (clickCount == 2)
			{
				let item = mListAdapter.GetItem(position);
				if (item == null) return;

				if (item.IsFolder)
				{
					let folderName = new String(item.Name);
					mContentList.Context?.MutationQueue.QueueAction(new () => {
						mListAdapter.NavigateInto(folderName);
						mGridAdapter.NavigateInto(folderName);
						breadcrumb.SetPath(
							mListAdapter.ActiveRegistry?.Name ?? "",
							mListAdapter.CurrentFolder);
						delete folderName;
					});
				}
				else if (item.IsRegistered)
				{
					ConfirmSelection();
					Close(.OK);
				}
			}
		});

		// Grid double-click -> navigate folder or select asset
		mContentGrid.OnItemDoubleClicked.Add(new (position) => {
			let item = mGridAdapter.GetItem(position);
			if (item == null) return;

			if (item.IsFolder)
			{
				let folderName = new String(item.Name);
				mContentGrid.Context?.MutationQueue.QueueAction(new () => {
					mListAdapter.NavigateInto(folderName);
					mGridAdapter.NavigateInto(folderName);
					breadcrumb.SetPath(
						mListAdapter.ActiveRegistry?.Name ?? "",
						mListAdapter.CurrentFolder);
					delete folderName;
				});
			}
			else if (item.IsRegistered)
			{
				ConfirmSelection();
				Close(.OK);
			}
		});

		// View mode toggle
		listBtn.OnCheckedChanged.Add(new (btn, val) => {
			if (val)
			{
				gridBtn.IsChecked = false;
				mContentList.Visibility = .Visible;
				mContentGrid.Visibility = .Gone;
				mGridMode = false;
			}
		});
		gridBtn.OnCheckedChanged.Add(new (btn, val) => {
			if (val)
			{
				listBtn.IsChecked = false;
				mContentList.Visibility = .Gone;
				mContentGrid.Visibility = .Visible;
				mGridMode = true;
			}
		});

		// Breadcrumb navigation
		breadcrumb.OnSegmentClicked.Add(new (segmentIndex) => {
			let ctx = breadcrumb.Context;
			if (ctx == null) return;

			ctx.MutationQueue.QueueAction(new () => {
				let registry = mListAdapter.ActiveRegistry;
				if (registry == null) return;

				if (segmentIndex == 0)
				{
					mListAdapter.SetFolder(registry, "");
					mGridAdapter.SetFolder(registry, "");
				}
				else
				{
					let newPath = scope String();
					breadcrumb.BuildPathToSegment(segmentIndex, newPath);
					mListAdapter.SetFolder(registry, newPath);
					mGridAdapter.SetFolder(registry, newPath);
				}
				breadcrumb.SetPath(registry.Name, mListAdapter.CurrentFolder);
			});
		});

		// Select first registry by default
		if (mTreeAdapter.RootCount > 0)
		{
			let flatAdapter = treeView.FlatAdapter;
			if (flatAdapter != null && flatAdapter.ItemCount > 0)
			{
				let firstNodeId = flatAdapter.GetNodeId(0);
				mTreeAdapter.SelectNode(firstNodeId);
			}
		}

		SetContent(split);
	}

	/// Gets the currently selected item from whichever view is active.
	private AssetContentItem GetSelectedItem()
	{
		if (mGridMode)
		{
			let sel = mContentGrid.Selection.FirstSelected;
			if (sel >= 0)
				return mGridAdapter.GetItem(sel);
		}
		else
		{
			let sel = mContentList.Selection.FirstSelected;
			if (sel >= 0)
				return mListAdapter.GetItem(sel);
		}
		return null;
	}

	/// Confirms the current selection and invokes the callback.
	private void ConfirmSelection()
	{
		let item = GetSelectedItem();
		if (item == null || !item.IsRegistered || item.IsFolder)
			return;

		let registry = mListAdapter.ActiveRegistry;
		if (registry == null) return;

		// Build protocol path
		let protocolPath = scope String();
		if (registry.Name.Length > 0)
			protocolPath.AppendF("{}://{}", registry.Name, item.RelativePath);
		else
			protocolPath.Set(item.RelativePath);

		mOnSelected?.Invoke(protocolPath, item.RegistryId);
	}
}
