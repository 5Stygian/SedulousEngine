namespace Sedulous.Engine.Core;

using System;
using System.IO;
using System.Collections;
using Sedulous.Resources;
using Sedulous.Serialization;
using Sedulous.Engine.Core.Resources;

/// Manages PrefabReferenceComponents: resolves prefab ResourceRefs,
/// instantiates entity subtrees, applies overrides, handles cleanup.
class PrefabComponentManager : ComponentManager<PrefabReferenceComponent>
{
	public override StringView SerializationTypeId => "Sedulous.PrefabReferenceComponent";

	/// Resource system for resolving prefab refs (set by subsystem or app).
	public ResourceSystem ResourceSystem { get; set; }

	/// Serializer provider for reading .prefab files during instantiation.
	public ISerializerProvider SerializerProvider { get; set; }

	/// Type registry for component deserialization during instantiation.
	public ComponentTypeRegistry TypeRegistry { get; set; }

	/// Per-component resource resolution tracking.
	private Dictionary<EntityHandle, ResolvedResource<PrefabResource>> mResolveStates = new .() ~ {
		for (var kv in _) kv.value.Release();
		delete _;
	};

	/// Prefab Guids currently being instantiated (cycle detection stack).
	private List<Guid> mInstantiationStack = new .() ~ delete _;

	protected override void OnRegisterUpdateFunctions()
	{
		// Resolve and instantiate every frame (presentation - always runs).
		// Priority 14: run before animation/render resolution.
		RegisterUpdate(.PostUpdate, new => ResolveAndInstantiate, 14);
	}

	private void ResolveAndInstantiate(float deltaTime)
	{
		if (ResourceSystem == null || SerializerProvider == null) return;

		for (let comp in ActiveComponents)
		{
			if (!comp.IsActive || !comp.PrefabRef.IsValid)
				continue;

			// Get or create resolve state for this component
			if (!mResolveStates.ContainsKey(comp.Owner))
				mResolveStates[comp.Owner] = .();
			var state = ref mResolveStates[comp.Owner];

			// Resolve ResourceRef -> PrefabResource (returns true if changed)
			if (state.Resolve(ResourceSystem, comp.PrefabRef))
			{
				let prefab = state.Handle.Resource;
				if (prefab == null) continue;

				// Resource changed - re-instantiate
				if (comp.IsInstantiated)
					DestroyInstantiatedEntities(comp);

				InstantiatePrefab(comp, prefab);
			}
		}
	}

	/// Instantiates a prefab's entities directly into the live scene under
	/// the component's owning entity. Uses PrefabSerializer.Instantiate which
	/// deserializes into the existing scene - component managers already on the
	/// scene (injected by ISceneAware subsystems) handle resource resolution.
	private void InstantiatePrefab(PrefabReferenceComponent comp, PrefabResource prefab)
	{
		let scene = Scene;
		if (scene == null) return;

		// Cycle detection
		if (mInstantiationStack.Contains(prefab.Id))
		{
			Console.WriteLine("WARNING: Prefab cycle detected - {} references itself", prefab.Name);
			return;
		}
		mInstantiationStack.Add(prefab.Id);
		defer { mInstantiationStack.RemoveAt(mInstantiationStack.Count - 1); }

		let path = scope String();
		if (prefab.SourcePath.Length > 0)
			path.Set(prefab.SourcePath);
		if (path.Length == 0) return;

		let text = scope String();
		if (File.ReadAllText(path, text) case .Err) return;

		let reader = SerializerProvider.CreateReader(text);
		if (reader == null) return;
		defer delete reader;

		// Instantiate directly into the live scene. PrefabSerializer.Instantiate
		// reads "ExposedParameters" and "Entities" by name from the document -
		// the Resource header fields (_type, _id, etc.) are ignored.
		// Components are deserialized into the scene's existing managers (which
		// have proper GPU resources, resolvers, etc. wired by ISceneAware).
		let prefabSerializer = scope PrefabSerializer(TypeRegistry);
		let emptyParams = scope List<ExposedParameterDescriptor>();

		let result = prefabSerializer.Instantiate(scene, comp.Owner, reader, emptyParams);
		if (result case .Ok(let guidMap))
		{
			comp.GuidMap = guidMap;
			for (let kv in guidMap)
				comp.InstantiatedEntities.Add(kv.value);

			// Add PrefabInstanceTags to all instantiated entities
			let tagMgr = GetOrCreateTagManager(scene);
			if (tagMgr != null)
			{
				for (let kv in guidMap)
				{
					let tagHandle = tagMgr.CreateComponent(kv.value);
					if (let tag = tagMgr.Get(tagHandle))
					{
						tag.PrefabId = prefab.Id;
						tag.SourceEntityId = kv.key;
						tag.ReferenceEntity = comp.Owner;
					}
				}
			}

			comp.IsInstantiated = true;
			comp.ResolvedPrefabId = prefab.Id;
		}
	}

	/// Destroys all entities created by a previous instantiation.
	private void DestroyInstantiatedEntities(PrefabReferenceComponent comp)
	{
		let scene = Scene;
		if (scene == null) return;

		for (let entity in comp.InstantiatedEntities)
		{
			if (scene.IsValid(entity))
				scene.DestroyEntity(entity);
		}
		comp.InstantiatedEntities.Clear();

		if (comp.GuidMap != null)
		{
			delete comp.GuidMap;
			comp.GuidMap = null;
		}

		comp.IsInstantiated = false;
	}

	private PrefabInstanceTagManager GetOrCreateTagManager(Scene scene)
	{
		let existing = scene.GetModule<PrefabInstanceTagManager>();
		if (existing != null) return existing;

		let mgr = new PrefabInstanceTagManager();
		scene.AddModule(mgr);
		return mgr;
	}

	public override void OnEntityDestroyed(EntityHandle entity)
	{
		// Clean up instantiated entities when the reference entity is destroyed
		let comp = GetForEntity(entity);
		if (comp != null && comp.IsInstantiated)
			DestroyInstantiatedEntities(comp);

		// Clean up resolve state
		if (mResolveStates.ContainsKey(entity))
		{
			var resolveState = ref mResolveStates[entity];
			resolveState.Release();
			mResolveStates.Remove(entity);
		}

		base.OnEntityDestroyed(entity);
	}
}
