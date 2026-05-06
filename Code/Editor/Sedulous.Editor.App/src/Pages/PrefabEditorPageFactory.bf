namespace Sedulous.Editor.App;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.VG.Renderer;
using Sedulous.Shell.Input;
using Sedulous.Engine.Core;
using Sedulous.Engine.Core.Resources;
using Sedulous.Engine.Render;
using Sedulous.Editor.Core;
using Sedulous.Resources;
using Sedulous.Engine;

/// Creates SceneEditorPage instances for .prefab files.
/// Prefabs open in the same scene editor as scenes — they're just
/// mini-scenes with an entity subgraph. Save serializes back as .prefab.
class PrefabEditorPageFactory : IEditorPageFactory
{
	private IDevice mDevice;
	private VGRenderer mVGRenderer;
	private IKeyboard mKeyboard;
	private ComponentTypeRegistry mTypeRegistry;

	public this(IDevice device, VGRenderer vgRenderer, IKeyboard keyboard,
		ComponentTypeRegistry typeRegistry)
	{
		mDevice = device;
		mVGRenderer = vgRenderer;
		mKeyboard = keyboard;
		mTypeRegistry = typeRegistry;
	}

	public void GetSupportedExtensions(List<String> outExtensions)
	{
		outExtensions.Add(new .(".prefab"));
	}

	public bool CanOpen(StringView path)
	{
		return path.EndsWith(".prefab", .OrdinalIgnoreCase);
	}

	public IEditorPage CreatePage(StringView path, EditorContext context)
	{
		let runtimeContext = context.RuntimeContext;
		if (runtimeContext == null) return null;

		let sceneSub = runtimeContext.GetSubsystem<SceneSubsystem>();
		if (sceneSub == null) return null;

		// Extract prefab name from filename
		let prefabName = scope String();
		System.IO.Path.GetFileNameWithoutExtension(path, prefabName);

		let scene = sceneSub.CreateScene(prefabName);
		scene.SimulationEnabled = false;

		// Read and deserialize prefab file
		let text = scope String();
		if (System.IO.File.ReadAllText(path, text) case .Err)
		{
			sceneSub.DestroyScene(scene);
			return null;
		}

		let reader = context.ResourceSystem?.SerializerProvider?.CreateReader(text);
		if (reader == null)
		{
			sceneSub.DestroyScene(scene);
			return null;
		}
		defer delete reader;

		// Deserialize via PrefabResource (loads entities into scene)
		let tempResource = scope PrefabResource();
		tempResource.Scene = scene;
		tempResource.TypeRegistry = mTypeRegistry;
		tempResource.Serialize(reader);

		// Create page (reuses same SceneEditorPage as scenes)
		let page = new SceneEditorPage(scene, path, context);

		let sceneRenderer = runtimeContext.GetSubsystemByInterface<ISceneRenderer>();
		let content = ScenePageBuilder.Build(page, context, mDevice, mVGRenderer,
			sceneRenderer, mKeyboard);
		page.SetContentView(content);

		return page;
	}
}
