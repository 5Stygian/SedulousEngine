namespace Sedulous.Editor.App;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Runtime;
using Sedulous.Runtime.Client;
using Sedulous.Shell;
using Sedulous.Shell.Input;
using Sedulous.Shaders;
using Sedulous.Fonts;
using Sedulous.Fonts.TTF;
using Sedulous.VG;
using Sedulous.VG.Renderer;
using Sedulous.UI;
using Sedulous.UI.Shell;
using Sedulous.UI.Toolkit;
using Sedulous.Core.Mathematics;
using Sedulous.Editor.Core;
using Sedulous.UI.Viewport;
using Sedulous.Profiler;
using Sedulous.Engine.Core;
using Sedulous.Core;
using Sedulous.Core.Logging.Abstractions;
using Sedulous.Engine.Core.Resources;
using Sedulous.Engine;
using Sedulous.Engine.Render;
using Sedulous.Geometry.Resources;
using Sedulous.Resources;
using Sedulous.Textures.Importer;
using Sedulous.Textures.Resources;
using Sedulous.Engine.Navigation;
using Sedulous.Engine.Audio;
using Sedulous.Engine.Animation;
using Sedulous.Engine.Physics;
using Sedulous.Models.FBX;
using Sedulous.Models.GLTF;
using Sedulous.Images.STB;
using System.IO;
using Sedulous.Serialization;
using Sedulous.Materials;
using Sedulous.Materials.Resources;

/// The Sedulous Editor application.
/// Extends Runtime.Client.Application for direct control over UI and rendering.
/// Creates a RuntimeContext with engine subsystems for scene preview.
class EditorApplication : Application, IDockableWindowHost
{
	// Runtime context (embedded engine for scene preview)
	// Deleted explicitly in OnShutdown before Device is destroyed.
	private Context mRuntimeContext;

	// Scene serialization (owned)
	private ComponentTypeRegistry mTypeRegistry ~ delete _;
	private SceneResourceManager mSceneManager ~ delete _;
	private PrefabResourceManager mPrefabManager ~ delete _;

	// Default primitive registry
	private ResourceRegistry mPrimitiveRegistry ~ delete _;

	// Project asset registry
	private ResourceRegistry mProjectRegistry ~ delete _;

	// Editor context (service locator for plugins, pages, panels)
	private EditorContext mEditorContext ~ delete _;

	// UI (owned directly, not via subsystem)
	private UIContext mUIContext;
	private RootView mMainRoot;
	private FontService mFontService ~ delete _;
	private VGContext mVGContext ~ delete _;
	private VGRenderer mVGRenderer;
	private VGExternalTextureCache mExternalTextureCache = new .() ~ delete _;
	private ShaderSystem mShaderSystem;
	private ShellClipboardAdapter mClipboard ~ delete _;
	private UIInputHelper mInputHelper = new .() ~ delete _;
	private float mFrameDelta;

	// Logging
	private EditorLogger mEditorLogger;
	private EditorLogBuffer mLogBuffer = new .() ~ delete _;

	// Editor state
	private bool mProjectLoaded;
	private View mProjectPickerView;
	private View mEditorShellView;
	private EditorProject mProject = new .() ~ delete _;
	private RecentProjects mRecentProjects = new .() ~ delete _;
	private DockablePanel mPlaceholderPanel; // "Open an asset..." placeholder, removed when first page opens
	private AssetBrowserPanel mAssetBrowserPanel ~ delete _;
	private LogView mLogView;
	private Dictionary<ObjectKey<IEditorPage>, DockablePanel> mPageDockPanels = new .() ~ delete _;
	private int32 mNewSceneCounter;

	// Multi-window (floating dock panels + cross-window drag)
	private Dictionary<View, SecondaryWindowContext> mDockableWindowMap = new .() ~ delete _;
	private IWindow mDragSourceWindow;
	private float mDragWindowOffsetX;
	private float mDragWindowOffsetY;

	public this() : base() { }

	protected override ILogger CreateLogger()
	{
		mEditorLogger = new EditorLogger();
		mEditorLogger.AddListener(mLogBuffer);
		return mEditorLogger;
	}

	protected override void OnInitialize(Context context)
	{
		// Initialize model and image loaders
		STBImageLoader.Initialize();
		GltfModels.Initialize();
		FbxModels.Initialize();

		// Shader system
		mShaderSystem = new ShaderSystem();
		let shaderDir = scope String();
		GetAssetPath("shaders", shaderDir);
		StringView[1] shaderPaths = .(shaderDir);
		
		let shaderCacheDir = scope String();
		GetAssetCachePath("shaders", shaderCacheDir);
		mShaderSystem.Initialize(Device, shaderPaths, shaderCacheDir);

		// Font service
		mFontService = new FontService();
		let fontPath = scope String();
		GetAssetPath("fonts/roboto/Roboto-Regular.ttf", fontPath);
		if (System.IO.File.Exists(fontPath))
		{
			float[?] sizes = .(11, 12, 13, 14, 16, 18, 20, 24);
			for (let size in sizes)
				mFontService.LoadFont("Roboto", fontPath, .() { PixelHeight = size });
		}

		// VG renderer (for UI drawing)
		mVGContext = new VGContext(mFontService);
		mVGRenderer = new VGRenderer();
		mVGRenderer.Initialize(Device, SwapChain.Format, (int32)SwapChain.BufferCount, mShaderSystem);
		mVGRenderer.SetExternalCache(mExternalTextureCache);

		// Clipboard
		mClipboard = new ShellClipboardAdapter(Shell.Clipboard);

		// Editor icons (shared SVG drawables)
		EditorIcons.Initialize();

		// UI context
		Sedulous.UI.ThemeRegistry.RegisterExtension(new ToolkitThemeExtension());
		Sedulous.UI.ThemeRegistry.RegisterExtension(new EditorThemeExtension());
		mUIContext = new UIContext();
		mUIContext.FontService = mFontService;
		mUIContext.Clipboard = mClipboard;
		mUIContext.StyleSheet = DarkTheme.Create();
		mUIContext.StyleSheet.ReleaseRef();

		mMainRoot = new RootView();
		mUIContext.AddRootView(mMainRoot);

		// Runtime context (embedded engine for scene preview)
		mRuntimeContext = new Context();
		mTypeRegistry = new ComponentTypeRegistry();

		// Register engine subsystems for scene rendering.
		// SceneSubsystem manages scene lifecycle.
		mRuntimeContext.RegisterSubsystem(new SceneSubsystem(mResourceSystem, mTypeRegistry));

		// RenderSubsystem provides ISceneRenderer for viewport rendering.
		let renderSub = new RenderSubsystem(mResourceSystem);
		renderSub.Device = Device;
		renderSub.Window = Window;
		renderSub.ShaderSystem = mShaderSystem;
		mRuntimeContext.RegisterSubsystem(renderSub);

		// Register all engine subsystems so all component types are available
		// in the editor (Add Component, inspector, scene serialization).
		mRuntimeContext.RegisterSubsystem(new PhysicsSubsystem());
		mRuntimeContext.RegisterSubsystem(new AnimationSubsystem(mResourceSystem));
		mRuntimeContext.RegisterSubsystem(new AudioSubsystem(mResourceSystem));
		mRuntimeContext.RegisterSubsystem(new NavigationSubsystem());

		let uiSub = new Sedulous.Engine.UI.EngineUISubsystem();
		uiSub.Device = Device;
		uiSub.Window = Window;
		uiSub.Shell = Shell;
		uiSub.ShaderSystem = mShaderSystem;
		let uiAssetDir = scope String();
		GetAssetPath("", uiAssetDir);
		uiSub.AssetDirectory = new String(uiAssetDir);
		mRuntimeContext.RegisterSubsystem(uiSub);

		mRuntimeContext.Startup();

		// Default primitive assets + registry
		EnsureDefaultAssets();

		// Scene serialization
		mSceneManager = new SceneResourceManager(mTypeRegistry, ResourceSystem.SerializerProvider);
		mPrefabManager = new PrefabResourceManager(mTypeRegistry, ResourceSystem.SerializerProvider);

		// Editor context
		mEditorContext = new EditorContext();
		mEditorContext.RuntimeContext = mRuntimeContext;
		mEditorContext.SceneManager = mSceneManager;
		mEditorContext.PrefabManager = mPrefabManager;
		mEditorContext.PageManager = new EditorPageManager();
		mEditorContext.SceneEditor = new EditorSceneManager();
		mEditorContext.AssetSelection = new AssetSelection();
		mEditorContext.PluginRegistry = new EditorPluginRegistry();
		mEditorContext.Project = mProject;
		mEditorContext.DialogService = Shell.Dialogs;
		mEditorContext.Shell = Shell;
		mEditorContext.ResourceSystem = mResourceSystem;

		// Discover plugins
		mEditorContext.PluginRegistry.DiscoverPlugins();

		// Recent projects
		let recentPath = scope String();
		GetAssetPath("cache/recent_projects.txt", recentPath);
		mRecentProjects.Initialize(recentPath);

		// Start with project picker
		BuildProjectPicker();

		mEditorLogger.Log(.Information, "Sedulous Editor initialized.");
	}

	protected override void OnContextStarted()
	{
		// Register built-in asset creators
		mEditorContext.RegisterAssetCreator(new MaterialAssetCreator());
		mEditorContext.RegisterAssetCreator(new SceneAssetCreator());
		mEditorContext.RegisterAssetCreator(new PrefabAssetCreator());

		// Register built-in asset importers
		mEditorContext.RegisterAssetImporter(new ModelAssetImporter());
		mEditorContext.RegisterAssetImporter(new TextureAssetImporter());

		// Register built-in page factories
		mEditorContext.RegisterPageFactory(new SceneEditorPageFactory(
			Device, mVGRenderer, Shell.InputManager.Keyboard, mTypeRegistry));
		mEditorContext.RegisterPageFactory(new PrefabEditorPageFactory(
			Device, mVGRenderer, Shell.InputManager.Keyboard, mTypeRegistry));
		mEditorContext.RegisterPageFactory(new TextureEditorPageFactory());
		mEditorContext.RegisterPageFactory(new MaterialEditorPageFactory());
		mEditorContext.RegisterPageFactory(new MeshEditorPageFactory());
		mEditorContext.RegisterPageFactory(new AnimationEditorPageFactory());
		mEditorContext.RegisterPageFactory(new SkeletonEditorPageFactory());
		mEditorContext.RegisterPageFactory(new AnimGraphEditorPageFactory());
		mEditorContext.RegisterPageFactory(new AudioClipEditorPageFactory());
		mEditorContext.RegisterPageFactory(new SoundCueEditorPageFactory());
		mEditorContext.RegisterPageFactory(new PropAnimEditorPageFactory());
		mEditorContext.RegisterPageFactory(new ParticleEditorPageFactory());

		// Register built-in gizmo renderers
		mEditorContext.RegisterGizmoRenderer(typeof(LightComponent), new LightGizmoRenderer());

		// Initialize plugins after UI is set up.
		mEditorContext.PluginRegistry.InitializeAll(mEditorContext);
	}

	// ==================== Project Picker ====================

	private void BuildProjectPicker()
	{
		let picker = new Panel();
		picker.Background = new ColorDrawable(.(30, 32, 40, 255));
		picker.Padding = .(40);

		let center = new FlexLayout();
		center.Direction = .Vertical;
		center.Spacing = 16;

		let title = new Label();
		title.SetText("Sedulous Editor");
		title.FontSize = 24;
		title.HAlign = .Center;
		center.AddView(title, new FlexLayout.LayoutParams() {
			Width = .Match, Height = .Fixed(.Px(32))
		});

		let subtitle = new Label();
		subtitle.SetText("Select a project to get started");
		subtitle.FontSize = 13;
		subtitle.HAlign = .Center;
		center.AddView(subtitle, new FlexLayout.LayoutParams() {
			Width = .Match, Height = .Fixed(.Px(20))
		});

		// Button row
		let btnRow = new FlexLayout();
		btnRow.Direction = .Horizontal;
		btnRow.Spacing = 12;

		let newBtn = new Button("New Project...");
		newBtn.OnClick.Add(new (b) => {
			Shell.Dialogs.ShowFolderDialog(new (paths) => {
				if (paths.Length > 0 && paths[0].Length > 0)
				{
					let path = scope String(paths[0]);
					mProject.Open(path);
					mProject.Save();
					OpenProject(path);
				}
			}, default, Window);
		});
		btnRow.AddView(newBtn, new FlexLayout.LayoutParams() { Height = .Fixed(.Px(32)) });

		let openBtn = new Button("Open Project...");
		openBtn.OnClick.Add(new (b) => {
			Shell.Dialogs.ShowFolderDialog(new (paths) => {
				if (paths.Length > 0 && paths[0].Length > 0)
					OpenProject(paths[0]);
			}, default, Window);
		});
		btnRow.AddView(openBtn, new FlexLayout.LayoutParams() { Height = .Fixed(.Px(32)) });

		center.AddView(btnRow, new FlexLayout.LayoutParams() {
			Width = .Match, Height = .Wrap
		});

		// Recent projects list
		if (mRecentProjects.Count > 0)
		{
			let recentLabel = new Label();
			recentLabel.SetText("Recent Projects:");
			recentLabel.FontSize = 12;
			center.AddView(recentLabel, new FlexLayout.LayoutParams() {
				Width = .Match, Height = .Fixed(.Px(20))
			});

			for (int i = 0; i < mRecentProjects.Count; i++)
			{
				let idx = i;
				let btn = new Button(mRecentProjects.Get(i));
				btn.OnClick.Add(new (b) => {
					if (idx < mRecentProjects.Count)
						OpenProject(mRecentProjects.Get(idx));
				});
				center.AddView(btn, new FlexLayout.LayoutParams() {
					Width = .Match, Height = .Fixed(.Px(28))
				});
			}
		}

		picker.AddView(center, new LayoutParams() {
			Width = .Wrap, Height = .Wrap
		});

		mProjectPickerView = picker;
		mMainRoot.AddView(picker, new LayoutParams() {
			Width = .Match, Height = .Match
		});
	}

	// ==================== Project Open ====================

	private void OpenProject(StringView path)
	{
		if (mProject.Open(path) case .Err)
		{
			mEditorLogger.Log(.Error, "Failed to open project: {}", path);
			return;
		}

		mRecentProjects.Add(path);
		mProjectLoaded = true;
		mEditorLogger.Log(.Information, "Project opened: {}", path);

		// Load or create project registry
		let projectDir = scope String();
		projectDir.Set(mProject.ProjectDirectory);
		let projRegistryPath = scope String()..AppendF("{}/project.registry", projectDir);

		if (mProjectRegistry != null)
		{
			ResourceSystem.RemoveRegistry(mProjectRegistry);
			delete mProjectRegistry;
		}

		mProjectRegistry = new Sedulous.Resources.ResourceRegistry("project", projectDir);
		if (System.IO.File.Exists(projRegistryPath))
			mProjectRegistry.LoadFromFile(projRegistryPath);
		ResourceSystem.AddRegistry(mProjectRegistry);
		mEditorLogger.Log(.Information, scope String()..AppendF("Project registry loaded ({} entries)", mProjectRegistry.Count));

		// Defer view switch - the button that triggered this is inside the picker.
		// Deleting immediately would use-after-free in Button.FireClick.
		if (mProjectPickerView != null)
		{
			let pickerToRemove = mProjectPickerView;
			mProjectPickerView = null;
			mUIContext.MutationQueue.QueueAction(new () => {
				mMainRoot.RemoveView(pickerToRemove, true);
				BuildEditorShell();
			});
		}
	}

	private void BuildEditorShell()
	{
		let shell = new FlexLayout();
		shell.Direction = .Vertical;

		// Menu bar
		let menuBar = new MenuBar();
		BuildMenus(menuBar);
		mEditorContext.MenuBar = menuBar;
		shell.AddView(menuBar, new FlexLayout.LayoutParams() {
			Width = .Match, Height = .Wrap
		});

		// Dock manager (center area)
		let dockManager = new DockManager();
		dockManager.DockableWindowHost = this;
		mEditorContext.DockManager = dockManager;
		shell.AddView(dockManager, new FlexLayout.LayoutParams() {
			Width = .Match, Grow = 1
		});

		// Placeholder panel (center) - shown until first page is opened.
		let placeholderContent = new Label();
		placeholderContent.SetText("Open an asset from the Asset Browser, or File > New Scene");
		placeholderContent.FontSize = 14;
		placeholderContent.HAlign = .Center;
		placeholderContent.VAlign = .Middle;
		placeholderContent.TextColor = .(100, 100, 115, 255);
		mPlaceholderPanel = dockManager.AddPanel("Editor", placeholderContent);
		mPlaceholderPanel.OnCloseRequested.Add(new (p) => { mPlaceholderPanel = null; });
		dockManager.DockPanel(mPlaceholderPanel, .Center);

		// Wire page manager events - each page gets its own dock tab.
		mEditorContext.PageManager.OnPageOpened.Add(new (page) => OnPageOpened(page));
		mEditorContext.PageManager.OnPageClosed.Add(new (page) => OnPageClosed(page));

		// Asset browser panel (bottom)
		mAssetBrowserPanel = new AssetBrowserPanel(mEditorContext);
		let assetsPanel = dockManager.AddPanel("Assets", mAssetBrowserPanel.ContentView);
		dockManager.DockPanelRelativeTo(assetsPanel, .Bottom, mPlaceholderPanel.Parent);

		// Console panel (bottom tab with assets)
		mLogView = new LogView();
		mLogBuffer.SetLogView(mLogView); // Flushes buffered startup logs
		let consolePanel = dockManager.AddPanel("Console", mLogView);
		dockManager.DockPanelRelativeTo(consolePanel, .Center, assetsPanel.Parent);

		// Set split ratio for page area vs bottom panels (70/30)
		if (let split = assetsPanel.Parent?.Parent as DockSplit)
			split.SplitRatio = 0.7f;

		// Status bar
		let statusBar = new StatusBar();
		statusBar.AddSection("Ready");
		shell.AddView(statusBar, new FlexLayout.LayoutParams() {
			Width = .Match, Height = .Wrap
		});

		mEditorShellView = shell;
		mMainRoot.AddView(shell, new LayoutParams() {
			Width = .Match, Height = .Match
		});
	}

	private void BuildMenus(MenuBar menuBar)
	{
		let fileMenu = menuBar.AddMenu("File");
		fileMenu.AddItem("New Scene", new () => OnNewScene());
		fileMenu.AddItem("Open Scene...", new () => OnOpenScene());
		fileMenu.AddSeparator();
		fileMenu.AddItem("Save", new () => OnSave());
		fileMenu.AddItem("Save As...", new () => OnSaveAs());
		fileMenu.AddSeparator();
		fileMenu.AddItem("Exit", new () => Exit());

		let editMenu = menuBar.AddMenu("Edit");
		editMenu.AddItem("Undo", new () => {
			mEditorContext.PageManager.ActivePage?.CommandStack.Undo();
		});
		editMenu.AddItem("Redo", new () => {
			mEditorContext.PageManager.ActivePage?.CommandStack.Redo();
		});

		let viewMenu = menuBar.AddMenu("View");
		viewMenu.AddItem("Console", new () => { /* TODO: toggle console panel */ });
		viewMenu.AddItem("Asset Browser", new () => { /* TODO: toggle assets panel */ });
	}

	private void OnOpenScene()
	{
		let defaultPath = scope String();
		if (mProject.ProjectDirectory.Length > 0)
			defaultPath.Set(mProject.ProjectDirectory);

		Shell.Dialogs.ShowOpenFileDialog(
			new (paths) => {
				if (paths.Length > 0)
					OpenSceneFile(paths[0]);
			},
			scope StringView[]("*.scene"),
			defaultPath, false, Window);
	}

	private void OnSave()
	{
		let page = mEditorContext.PageManager.ActivePage;
		if (page == null) return;

		if (page.FilePath.Length == 0)
			OnSaveAs();
		else
		{
			page.Save();
			SyncDockPanelTitle(page);
			RegisterInProjectRegistry(page);
		}
	}

	private void OnSaveAs()
	{
		let page = mEditorContext.PageManager.ActivePage;
		if (page == null) return;

		let defaultPath = scope String();
		if (mProject.ProjectDirectory.Length > 0)
			defaultPath.Set(mProject.ProjectDirectory);

		Shell.Dialogs.ShowSaveFileDialog(
			new (paths) => {
				if (paths.Length > 0)
				{
					let savePath = scope String(paths[0]);
					if (!savePath.EndsWith(".scene", .OrdinalIgnoreCase))
						savePath.Append(".scene");
					page.SaveAs(savePath);
					SyncDockPanelTitle(page);
					RegisterInProjectRegistry(page);
				}
			},
			scope StringView[]("*.scene"),
			defaultPath, Window);
	}

	private void SyncDockPanelTitle(IEditorPage page)
	{
		let key = Sedulous.Core.ObjectKey<IEditorPage>(page);
		if (mPageDockPanels.TryGetValue(key, let panel))
			panel.SetTitle(page.Title);
	}

	private void RegisterInProjectRegistry(IEditorPage page)
	{
		if (mProjectRegistry == null || page.FilePath.Length == 0) return;

		if (let scenePage = page as SceneEditorPage)
		{
			let sceneGuid = scenePage.LastSavedGuid;
			if (sceneGuid == .Empty) return;

			// Convert absolute path to project-relative
			let projectDir = mProject.ProjectDirectory;
			let filePath = page.FilePath;

			let relativePath = scope String();
			if (filePath.StartsWith(projectDir))
			{
				var rel = filePath.Substring(projectDir.Length);
				if (rel.StartsWith("/") || rel.StartsWith("\\"))
					rel = rel.Substring(1);
				relativePath.Set(rel);
			}
			else
			{
				relativePath.Set(filePath);
			}

			relativePath.Replace('\\', '/');
			mProjectRegistry.Register(sceneGuid, relativePath);

			// Save registry to disk
			let registryPath = scope String()..AppendF("{}/project.registry", projectDir);
			mProjectRegistry.SaveToFile(registryPath);
			mEditorLogger.Log(.Information, scope String()..AppendF("Registered in project registry: {}", relativePath));
		}
	}

	private void OpenSceneFile(StringView path)
	{
		let page = mEditorContext.PageManager.OpenWithContext(path, mEditorContext);
		if (page != null)
			mEditorLogger.Log(.Information, scope String()..AppendF("Opened scene: {}", path));
		else
			mEditorLogger.Log(.Error, scope String()..AppendF("Failed to open: {}", path));
	}

	private void OnPageOpened(IEditorPage page)
	{
		if (page == null || page.ContentView == null) return;
		let dockManager = mEditorContext.DockManager;
		if (dockManager == null) return;

		// Create dock panel for this page.
		let panel = dockManager.AddPanel(page.Title, page.ContentView);
		panel.Closable = true;

		// When dock tab X is clicked, detach content (page owns it) and close via PageManager.
		// Note: DockManager's own OnCloseRequested handler (registered first in AddPanel)
		// calls ClosePanel before this handler runs, so the dock panel is already undocked.
		let capturedPage = page;
		panel.OnCloseRequested.Add(new (dp) => {
			// Detach content before dock manager deletes the panel.
			if (capturedPage.ContentView?.Parent != null)
				if (let parent = capturedPage.ContentView.Parent as ViewGroup)
					parent.RemoveView(capturedPage.ContentView, false);

			// Close through PageManager (fires OnPageClosed, handles cleanup + placeholder).
			mEditorContext.PageManager.Close(capturedPage);
		});

		// Dock in the right place.
		if (mPlaceholderPanel != null)
		{
			let placeholder = mPlaceholderPanel;
			mPlaceholderPanel = null;
			dockManager.DockPanelRelativeTo(panel, .Center, placeholder.Parent);
			dockManager.ClosePanel(placeholder);
		}
		else
		{
			// Subsequent pages: dock as tab next to existing pages.
			DockablePanel relativePanel = null;
			for (let kv in mPageDockPanels)
			{
				relativePanel = kv.value;
				break;
			}

			if (relativePanel != null)
				dockManager.DockPanelRelativeTo(panel, .Center, relativePanel.Parent);
			else
				dockManager.DockPanel(panel, .Center);
		}

		mPageDockPanels[.(page)] = panel;

		// Activate the new tab so the opened page is immediately visible
		dockManager.ActivatePanel(panel);
	}

	private void OnPageClosed(IEditorPage page)
	{
		let key = ObjectKey<IEditorPage>(page);

		// Detach content view from dock panel before the page deletes it.
		// During normal tab close, OnCloseRequested already did this.
		// During shutdown, PageManager.Close calls us directly - need to ensure detach.
		if (page.ContentView?.Parent != null)
			if (let parent = page.ContentView.Parent as ViewGroup)
				parent.RemoveView(page.ContentView, false);

		// Close the dock panel if it still exists.
		if (mPageDockPanels.TryGetValue(key, let panel))
			mEditorContext.DockManager?.ClosePanel(panel);

		mPageDockPanels.Remove(key);

		// If that was the last page, restore the placeholder panel.
		if (mPageDockPanels.Count == 0 && mPlaceholderPanel == null)
		{
			let dockManager = mEditorContext.DockManager;
			if (dockManager != null)
			{
				let placeholderContent = new Label();
				placeholderContent.SetText("Open an asset from the Asset Browser, or File > New Scene");
				placeholderContent.FontSize = 14;
				placeholderContent.HAlign = .Center;
				placeholderContent.VAlign = .Middle;
				placeholderContent.TextColor = .(100, 100, 115, 255);
				mPlaceholderPanel = dockManager.AddPanel("Editor", placeholderContent);
				mPlaceholderPanel.OnCloseRequested.Add(new (p) => { mPlaceholderPanel = null; });
				// Dock above the remaining root (console/assets) to recreate the original split
				dockManager.DockPanelRelativeTo(mPlaceholderPanel, .Top, dockManager.RootNode);
			}
		}
	}

	private void RenderActiveViewports(ICommandEncoder encoder, int32 frameIndex)
	{
		if (mEditorContext?.PageManager == null) return;

		// Render viewports only for scene pages whose panels are actually visible.
		// Inactive dock tabs have their DockablePanel set to Visibility=Gone,
		// so we walk ancestors to skip those - no point doing GPU work for
		// hidden viewports.
		for (let page in mEditorContext.PageManager.OpenPages)
		{
			if (let scenePage = page as SceneEditorPage)
			{
				if (scenePage.ContentView != null && !scenePage.ContentView.IsPendingDeletion
					&& IsViewEffectivelyVisible(scenePage.ContentView))
				{
					RenderViewportsInTree(scenePage.ContentView, encoder, frameIndex);
				}
			}
		}
	}

	/// Checks if a view and all its ancestors are Visible (not Gone/Collapsed).
	private static bool IsViewEffectivelyVisible(View view)
	{
		var v = view;
		while (v != null)
		{
			if (v.Visibility != .Visible)
				return false;
			v = v.Parent;
		}
		return true;
	}

	private void RenderViewportsInTree(View view, ICommandEncoder encoder, int32 frameIndex)
	{
		if (let viewport = view as ViewportView)
		{
			viewport.RenderContent(encoder, frameIndex);
			return;
		}

		if (let group = view as ViewGroup)
		{
			for (int i = 0; i < group.ChildCount; i++)
				RenderViewportsInTree(group.GetChildAt(i), encoder, frameIndex);
		}
	}

	// ==================== Default Assets ====================

	/// Ensures default builtin assets (primitives, materials) exist on disk.
	/// Creates them if missing, loads the registry, and adds it to ResourceSystem.
	private void EnsureDefaultAssets()
	{
		let assetRoot = scope String();
		GetAssetPath("", assetRoot);

		let registryPath = scope String();
		registryPath.AppendF("{}/builtin.registry", assetRoot);

		// Check if assets need generating
		bool needsGeneration = !File.Exists(registryPath);

		if (needsGeneration)
		{
			mEditorLogger.Log(.Information, "Generating default builtin assets...");
			let provider = ResourceSystem.SerializerProvider;
			let tempRegistry = scope ResourceRegistry();

			GenerateDefaultPrimitives(assetRoot, provider, tempRegistry);
			GenerateDefaultMaterials(assetRoot, provider, tempRegistry);
			GenerateDefaultSkies(assetRoot, provider, tempRegistry);

			tempRegistry.SaveToFile(registryPath);
			mEditorLogger.Log(.Information, "Default builtin assets generated.");
		}

		// Load builtin registry with name "builtin" and root = asset directory
		mPrimitiveRegistry = new ResourceRegistry("builtin", assetRoot);
		if (mPrimitiveRegistry.LoadFromFile(registryPath) case .Ok)
		{
			ResourceSystem.AddRegistry(mPrimitiveRegistry);
			mEditorLogger.Log(.Information, scope String()..AppendF("Builtin registry loaded ({} entries)", mPrimitiveRegistry.Count));
		}
		else
		{
			mEditorLogger.Log(.Warning, "Failed to load builtin registry.");
		}
	}

	private void GenerateDefaultPrimitives(StringView assetRoot, ISerializerProvider provider, ResourceRegistry registry)
	{
		let primDir = scope String()..AppendF("{}/primitives", assetRoot);
		if (!Directory.Exists(primDir))
			Directory.CreateDirectory(primDir);

		// Plane
		{
			let res = StaticMeshResource.CreatePlane(10, 10, 1, 1);
			res.Name = "Plane";
			let path = scope String()..AppendF("{}/plane.mesh", primDir);
			res.SaveToFile(path, provider);
			registry.Register(res.Id, "primitives/plane.mesh");
			delete res;
		}

		// Cube
		{
			let res = StaticMeshResource.CreateCube(1.0f);
			res.Name = "Cube";
			let path = scope String()..AppendF("{}/cube.mesh", primDir);
			res.SaveToFile(path, provider);
			registry.Register(res.Id, "primitives/cube.mesh");
			delete res;
		}

		// Sphere
		{
			let res = StaticMeshResource.CreateSphere(0.5f, 32, 16);
			res.Name = "Sphere";
			let path = scope String()..AppendF("{}/sphere.mesh", primDir);
			res.SaveToFile(path, provider);
			registry.Register(res.Id, "primitives/sphere.mesh");
			delete res;
		}
	}

	private void GenerateDefaultMaterials(StringView assetRoot, ISerializerProvider provider, ResourceRegistry registry)
	{
		let matDir = scope String()..AppendF("{}/materials", assetRoot);
		if (!Directory.Exists(matDir))
			Directory.CreateDirectory(matDir);

		// Default PBR material
		{
			let mat = Materials.CreatePBR("Default", "forward");
			let res = new MaterialResource(mat, true);
			res.Name = "Default";
			let path = scope String()..AppendF("{}/default.material", matDir);
			res.SaveToFile(path, provider);
			registry.Register(res.Id, "materials/default.material");
			delete res;
		}

		// Default Unlit material
		{
			let mat = Materials.CreateUnlit("DefaultUnlit");
			let res = new MaterialResource(mat, true);
			res.Name = "DefaultUnlit";
			let path = scope String()..AppendF("{}/default_unlit.material", matDir);
			res.SaveToFile(path, provider);
			registry.Register(res.Id, "materials/default_unlit.material");
			delete res;
		}
	}

	private void GenerateDefaultSkies(StringView assetRoot, ISerializerProvider provider, ResourceRegistry registry)
	{
		let skyDir = scope String()..AppendF("{}/skies", assetRoot);
		if (!Directory.Exists(skyDir))
			Directory.CreateDirectory(skyDir);

		// Realistic sky (equirectangular HDR)
		{
			let srcPath = scope String();
			GetAssetPath("textures/environment/BlueSky.hdr", srcPath);

			if (TextureImporter.ImportEquirectangular(srcPath) case .Ok(let res))
			{
				res.Name.Set("realistic_sky");
				let path = scope String()..AppendF("{}/realistic_sky.texture", skyDir);
				res.SaveToFile(path, provider);
				registry.Register(res.Id, "skies/realistic_sky.texture");
				delete res;
			}
		}

		// Stylized sky (equirectangular PNG)
		{
			let srcPath = scope String();
			GetAssetPath("textures/environment/sky_75_2k/sky_75_2k.png", srcPath);

			if (TextureImporter.ImportEquirectangular(srcPath) case .Ok(let res))
			{
				res.Name.Set("stylized_sky");
				let path = scope String()..AppendF("{}/stylized_sky.texture", skyDir);
				res.SaveToFile(path, provider);
				registry.Register(res.Id, "skies/stylized_sky.texture");
				delete res;
			}
		}
	}

	// ==================== Scene Creation ====================

	private void OnNewScene()
	{
		// Create scene through RuntimeContext's SceneSubsystem so ISceneAware
		// subsystems (RenderSubsystem) inject their component managers.
		let sceneSub = mRuntimeContext.GetSubsystem<SceneSubsystem>();
		if (sceneSub == null)
		{
			mEditorLogger.Log(.Error, "No SceneSubsystem in RuntimeContext");
			return;
		}

		mNewSceneCounter++;
		let sceneName = scope String();
		sceneName.AppendF("Untitled {}", mNewSceneCounter);
		let scene = sceneSub.CreateScene(sceneName);

		// Editor mode: disable simulation so physics, animation, particles don't tick.
		// Play mode (future) will re-enable via scene.Start().
		scene.SimulationEnabled = false;

		// Create default camera
		let cameraEntity = scene.CreateEntity("Main Camera");
		scene.SetLocalTransform(cameraEntity, .() {
			Position = .(0, 2, 5),
			Rotation = .Identity,
			Scale = .One
		});

		// Add CameraComponent
		let cameraMgr = scene.GetModule<CameraComponentManager>();
		if (cameraMgr != null)
		{
			let camHandle = cameraMgr.CreateComponent(cameraEntity);
			if (let cam = cameraMgr.Get(camHandle))
				cam.IsActiveCamera = true;
		}

		// Create default directional light
		let lightEntity = scene.CreateEntity("Directional Light");
		scene.SetLocalTransform(lightEntity, .() {
			Position = .(0, 5, 0),
			Rotation = .Identity,
			Scale = .One
		});

		let lightMgr = scene.GetModule<LightComponentManager>();
		if (lightMgr != null)
		{
			let lightHandle = lightMgr.CreateComponent(lightEntity);
			if (let light = lightMgr.Get(lightHandle))
			{
				light.Type = .Directional;
				light.Intensity = 2.0f;
			}
		}

		// Load primitive meshes from disk (generated by EnsureDefaultAssets)
		let meshMgr = scene.GetModule<MeshComponentManager>();

		// Ground plane
		let planeEntity = scene.CreateEntity("Ground");
		scene.SetLocalTransform(planeEntity, .() { Position = .Zero, Rotation = .Identity, Scale = .One });

		if (meshMgr != null)
		{
			if (ResourceSystem.LoadResource<StaticMeshResource>("builtin://primitives/plane.mesh") case .Ok(var handle))
			{
				var planeRef = ResourceRef(handle.Resource.Id, "builtin://primitives/plane.mesh");
				let planeComp = meshMgr.CreateComponent(planeEntity);
				if (let comp = meshMgr.Get(planeComp))
					comp.SetMeshRef(planeRef);
				planeRef.Dispose();
				handle.Release();
			}
		}

		// Cube
		let cubeEntity = scene.CreateEntity("Cube");
		scene.SetLocalTransform(cubeEntity, .() { Position = .(0, 0.5f, 0), Rotation = .Identity, Scale = .One });

		if (meshMgr != null)
		{
			if (ResourceSystem.LoadResource<StaticMeshResource>("builtin://primitives/cube.mesh") case .Ok(var handle))
			{
				var cubeRef = ResourceRef(handle.Resource.Id, "builtin://primitives/cube.mesh");
				let cubeComp = meshMgr.CreateComponent(cubeEntity);
				if (let comp = meshMgr.Get(cubeComp))
					comp.SetMeshRef(cubeRef);
				cubeRef.Dispose();
				handle.Release();
			}
		}

		// Create page with layout
		let page = new SceneEditorPage(scene, "", mEditorContext);

		let sceneRenderer = mRuntimeContext.GetSubsystemByInterface<ISceneRenderer>();
		let content = ScenePageBuilder.Build(page, mEditorContext, Device, mVGRenderer,
			sceneRenderer, Shell.InputManager.Keyboard);
		page.SetContentView(content);

		mEditorContext.PageManager.AddPage(page);
		mEditorLogger.Log(.Information, "Created new scene");
	}

	// ==================== Frame Loop ====================

	protected override void OnInput(FrameContext frame)
	{
		mFrameDelta = frame.DeltaTime;

		if (mUIContext == null) return;

		let mouse = Shell.InputManager.Mouse;
		let keyboard = Shell.InputManager.Keyboard;

		// F8 toggles UI debug overlay (all options at once).
		if (keyboard != null && keyboard.IsKeyPressed(.F8))
		{
			let on = !mUIContext.DebugSettings.ShowBounds;
			mUIContext.DebugSettings.ShowBounds = on;
			mUIContext.DebugSettings.ShowPadding = on;
			mUIContext.DebugSettings.ShowMargin = on;
			mUIContext.DebugSettings.ShowHitTarget = on;
			mUIContext.DebugSettings.ShowFocusPath = on;
		}

		// Keyboard shortcuts
		if (keyboard != null && keyboard.IsKeyDown(.LeftCtrl))
		{
			if (keyboard.IsKeyPressed(.S))
			{
				if (keyboard.IsKeyDown(.LeftShift))
					OnSaveAs();
				else
					OnSave();
			}
			else if (keyboard.IsKeyPressed(.O))
			{
				OnOpenScene();
			}
		}
		if (mouse == null) return;

		let dragDrop = mUIContext.DragDropManager;

		// Determine which window has the mouse.
		RootView inputRoot = mMainRoot;
		for (let kv in mDockableWindowMap)
		{
			if (kv.value.Window.Focused)
			{
				if (let data = kv.value.UserData as DockableWindowData)
					inputRoot = data.RootView;
				break;
			}
		}

		// Cross-window drag: move OS window, route input to main window.
		if ((dragDrop.IsDragging || dragDrop.IsPotentialDrag) && inputRoot !== mMainRoot)
		{
			let globalX = mouse.GlobalX;
			let globalY = mouse.GlobalY;

			// Capture drag offset on first frame.
			if (dragDrop.IsDragging && mDragSourceWindow == null)
			{
				for (let kv in mDockableWindowMap)
				{
					if (kv.value.Window.Focused)
					{
						mDragSourceWindow = kv.value.Window;
						mDragWindowOffsetX = globalX - (float)mDragSourceWindow.X;
						mDragWindowOffsetY = globalY - (float)mDragSourceWindow.Y;
						break;
					}
				}
			}

			// Move the dockable OS window to follow cursor.
			if (mDragSourceWindow != null)
			{
				mDragSourceWindow.X = (int32)(globalX - mDragWindowOffsetX);
				mDragSourceWindow.Y = (int32)(globalY - mDragWindowOffsetY);
			}

			// Route to main window with global-to-main-relative conversion.
			mUIContext.ActiveInputRoot = mMainRoot;
			let mx = globalX - (float)Window.X;
			let my = globalY - (float)Window.Y;
			mInputHelper.ProcessMouseInput(mouse, mUIContext, mx, my);
			if (keyboard != null)
				mInputHelper.ProcessKeyboardInput(keyboard, mUIContext, mFrameDelta);
			return;
		}

		// Not cross-window dragging - clear drag source.
		if (mDragSourceWindow != null)
			mDragSourceWindow = null;

		// Normal routing to focused window.
		mUIContext.ActiveInputRoot = inputRoot;
		mInputHelper.ProcessMouseInput(mouse, mUIContext);
		if (keyboard != null)
			mInputHelper.ProcessKeyboardInput(keyboard, mUIContext, mFrameDelta);
	}

	protected override void OnUpdate(FrameContext frame)
	{
		if (mUIContext == null) return;

		mFrameDelta = frame.DeltaTime;

		// Flush buffered log messages to the LogView on the main thread.
		mLogBuffer.Flush();

		// Tick RuntimeContext (component init, scene updates for editor mode).
		mRuntimeContext.BeginFrame(frame.DeltaTime);
		mRuntimeContext.Update(frame.DeltaTime);
		mRuntimeContext.PostUpdate(frame.DeltaTime);
		mRuntimeContext.EndFrame();

		// Update plugins
		mEditorContext.PluginRegistry.UpdateAll(frame.DeltaTime);

		// Update active page
		mEditorContext.PageManager.ActivePage?.Update(frame.DeltaTime);

		// UI frame
		mMainRoot.DpiScale = Window.ContentScale;
		mMainRoot.ViewportSize = .((float)Window.Width, (float)Window.Height);
		mUIContext.BeginFrame(frame.DeltaTime);
		mUIContext.UpdateRootView(mMainRoot);
	}

	protected override void OnPrepareFrame(FrameContext frame)
	{
		if (mUIContext == null || mVGContext == null || mVGRenderer == null) return;

		// Build VG geometry
		mVGContext.Clear();
		mUIContext.DrawRootView(mMainRoot, mVGContext);

		// Upload to GPU
		mVGRenderer.UpdateProjection(SwapChain.Width, SwapChain.Height, frame.FrameIndex);
		let batch = mVGContext.GetBatch();
		if (batch != null)
			mVGRenderer.Prepare(batch, frame.FrameIndex);
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		let encoder = render.Encoder;
		let frame = render.Frame;

		// Render active viewport views (3D scenes) to their offscreen textures
		// BEFORE UI rendering - the UI will display these textures via DrawImage.
		let sceneRenderer = mRuntimeContext?.GetSubsystemByInterface<ISceneRenderer>();
		if (sceneRenderer != null)
			sceneRenderer.BeginRendering(encoder, frame.FrameIndex);

		RenderActiveViewports(encoder, frame.FrameIndex);

		if (sceneRenderer != null)
			sceneRenderer.EndRendering();

		// Begin render pass for UI
		ColorAttachment[1] colorAttachments = .(.()
		{
			View = render.CurrentTextureView,
			LoadOp = .Clear,
			StoreOp = .Store,
			ClearValue = .(0.12f, 0.12f, 0.15f, 1)
		});

		RenderPassDesc passDesc = .() { ColorAttachments = .(colorAttachments) };
		let renderPass = encoder.BeginRenderPass(passDesc);
		if (renderPass != null)
		{
			mVGRenderer.Render(renderPass, SwapChain.Width, SwapChain.Height, frame.FrameIndex);
			renderPass.End();
		}

		return true;
	}

	// ==================== IDockableWindowHost ====================

	public bool SupportsOSWindows => true;

	public void CreateDockableWindow(View dockableWindow, float width, float height,
		float screenX, float screenY, delegate void(View) onCloseRequested = null)
	{
		let settings = Sedulous.Shell.WindowSettings()
		{
			Title = scope .("Float"),
			Width = (int32)width,
			Height = (int32)height,
			Resizable = true,
			Bordered = false
		};

		if (CreateSecondaryWindow(settings) case .Err)
		{
			Console.WriteLine("Failed to create floating OS window");
			delete onCloseRequested;
			return;
		}

		let ctx = mSecondaryWindows[mSecondaryWindows.Count - 1];
		ctx.Window.X = Window.X + (int32)screenX;
		ctx.Window.Y = Window.Y + (int32)screenY;

		let data = new DockableWindowData();
		data.OnCloseDelegate = onCloseRequested;
		if (onCloseRequested != null)
			ctx.OnCloseRequested = new (swCtx) => { data.OnCloseDelegate(dockableWindow); };
		else
			ctx.OnCloseRequested = new (swCtx) => { };

		data.RootView = new RootView();
		data.RootView.DpiScale = ctx.Window.ContentScale;
		data.RootView.ViewportSize = .((float)ctx.Window.Width, (float)ctx.Window.Height);
		mUIContext.AddRootView(data.RootView);
		data.RootView.AddView(dockableWindow);
		data.DockableView = dockableWindow;

		data.VGContext = new VGContext(mFontService);
		data.VGRenderer = new VGRenderer();
		data.VGRenderer.Initialize(Device, ctx.SwapChain.Format,
			(int32)ctx.SwapChain.BufferCount, mShaderSystem);
		data.VGRenderer.SetExternalCache(mExternalTextureCache);

		ctx.UserData = data;
		mDockableWindowMap[dockableWindow] = ctx;
	}

	public void DestroyDockableWindow(View dockableWindow)
	{
		DestroyDockableWindowImpl(dockableWindow);
	}

	public void MoveDockableWindow(View dockableWindow, float screenX, float screenY)
	{
		if (mDockableWindowMap.TryGetValue(dockableWindow, let ctx))
		{
			ctx.Window.X = Window.X + (int32)screenX;
			ctx.Window.Y = Window.Y + (int32)screenY;
		}
	}

	private void DestroyDockableWindowImpl(View dockableWindow, bool detachView = true)
	{
		if (!mDockableWindowMap.TryGetValue(dockableWindow, let ctx))
			return;

		mDockableWindowMap.Remove(dockableWindow);

		if (let data = ctx.UserData as DockableWindowData)
		{
			if (detachView && dockableWindow.Parent == data.RootView)
				data.RootView.RemoveView(dockableWindow, false);

			mUIContext.RemoveRootView(data.RootView);
			Device.WaitIdle();
			delete data;
		}

		ctx.UserData = null;
		DestroySecondaryWindow(ctx);
	}

	// ==================== Secondary Window Rendering ====================

	protected override void OnPrepareSecondaryFrame(SecondaryWindowContext ctx, FrameContext frame)
	{
		if (let data = ctx.UserData as DockableWindowData)
		{
			data.RootView.DpiScale = ctx.Window.ContentScale;
			data.RootView.ViewportSize = .((float)ctx.Window.Width, (float)ctx.Window.Height);
			mUIContext.UpdateRootView(data.RootView);
		}
	}

	protected override void OnRenderSecondaryWindow(SecondaryWindowContext ctx,
		IRenderPassEncoder renderPass, FrameContext frame)
	{
		if (let data = ctx.UserData as DockableWindowData)
		{
			let vg = data.VGContext;
			let renderer = data.VGRenderer;
			let w = ctx.SwapChain.Width;
			let h = ctx.SwapChain.Height;

			vg.Clear();
			mUIContext.DrawRootView(data.RootView, vg);
			let batch = vg.GetBatch();
			if (batch == null || batch.Commands.Count == 0)
				return;

			renderer.UpdateProjection(w, h, frame.FrameIndex);
			renderer.Prepare(batch, frame.FrameIndex);
			renderer.Render(renderPass, w, h, frame.FrameIndex);
		}
	}

	// ==================== Shutdown ====================

	protected override void OnShutdown()
	{
		// Shutdown plugins
		mEditorContext.PluginRegistry.ShutdownAll();

		// Detach all page content views from dock panels before pages are deleted.
		// Don't call ClosePanel - the view tree will be cascade-deleted by
		// RootView's destructor during UIContext cleanup.
		for (let page in mEditorContext.PageManager.OpenPages)
		{
			if (page.ContentView?.Parent != null)
				if (let parent = page.ContentView.Parent as ViewGroup)
					parent.RemoveView(page.ContentView, false);
		}
		mPageDockPanels.Clear();

		// Shutdown pages (deletes pages + their content views)
		mEditorContext.PageManager.Shutdown();

		// Close project
		mProject.Close();

		// Clean up editor context
		mEditorContext.Dispose();

		// Clean up runtime context (must be deleted before Device is destroyed
		// since its subsystems share the Device).
		mRuntimeContext.Shutdown();
		delete mRuntimeContext;
		mRuntimeContext = null;

		// Destroy floating windows (before UIContext so roots are removed cleanly)
		for (let kv in mDockableWindowMap)
			DestroyDockableWindowImpl(kv.key, detachView: false);
		mDockableWindowMap.Clear();

		// Clean up UI
		if (mUIContext != null)
		{
			mUIContext.RemoveRootView(mMainRoot);
			delete mUIContext;
			mUIContext = null;
		}

		delete mMainRoot;
		mMainRoot = null;

		EditorIcons.Shutdown();

		if (mVGRenderer != null)
		{
			mVGRenderer.Dispose();
			delete mVGRenderer;
			mVGRenderer = null;
		}

		mShaderSystem?.Dispose();
		delete mShaderSystem;
		mShaderSystem = null;
	}

	protected override void OnCleanup()
	{

	}

	protected override void OnResize(int32 width, int32 height)
	{
		// UI updates viewport on next frame via mMainRoot.ViewportSize
	}
}
