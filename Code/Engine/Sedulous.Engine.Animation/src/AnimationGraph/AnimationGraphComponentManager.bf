namespace Sedulous.Engine.Animation;

using System;
using System.Collections;
using Sedulous.Engine.Core;
using Sedulous.Resources;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
using Sedulous.Core.Mathematics;

/// Manages animation graph components: resolves skeleton + graph resources,
/// creates AnimationGraphPlayers, evaluates graph each frame.
///
/// Updates at PostUpdate with priority 11 - before SkeletalAnimationComponentManager
/// (priority 10) so graph output can override simple clip playback.
class AnimationGraphComponentManager : ComponentManager<AnimationGraphComponent>
{
	/// Resource system for resolving skeleton/graph refs.
	public ResourceSystem ResourceSystem { get; set; }

	/// Per-component resource resolution tracking.
	private Dictionary<EntityHandle, AnimGraphResolveState> mResolveStates = new .() ~ {
		for (let kv in _)
		{
			kv.value.Release();
			delete kv.value;
		}
		delete _;
	};

	public override StringView SerializationTypeId => "Sedulous.AnimationGraphComponent";

	protected override void OnRegisterUpdateFunctions()
	{
		// Resource resolution always runs (presentation).
		// Priority 13: run before simulation (priority 11) so resources are ready.
		RegisterUpdate(.PostUpdate, new => ResolveGraphResources, 13);

		// Graph evaluation advances animation state (simulation only).
		// Priority 11: run before SkeletalAnimationComponentManager (priority 10)
		RegisterUpdate(.PostUpdate, new => UpdateGraphs, 11, simulationOnly: true);
	}

	/// Resolves skeleton and graph resources. Always runs (presentation).
	private void ResolveGraphResources(float deltaTime)
	{
		if (ResourceSystem == null) return;

		for (let comp in ActiveComponents)
		{
			if (!comp.IsActive || !comp.Active) continue;

			ResolveResources(comp);

			// Create graph player once resources are ready
			if (comp.GraphPlayer == null && comp.Skeleton != null && comp.Graph != null)
				comp.GraphPlayer = new AnimationGraphPlayer(comp.Graph, comp.Skeleton);
		}
	}

	/// Evaluates animation graphs. Simulation only.
	private void UpdateGraphs(float deltaTime)
	{
		for (let comp in ActiveComponents)
		{
			if (!comp.IsActive || !comp.Active) continue;

			if (comp.GraphPlayer != null)
				comp.GraphPlayer.Update(deltaTime);
		}
	}

	private void ResolveResources(AnimationGraphComponent comp)
	{
		let state = GetOrCreateResolveState(comp.Owner);

		// Resolve skeleton
		if (state.Skeleton.Resolve(ResourceSystem, comp.SkeletonRef))
		{
			let res = state.Skeleton.Handle.Resource;
			comp.Skeleton = (res != null) ? res.Skeleton : null;
		}
		else if (!comp.SkeletonRef.IsValid && comp.Skeleton != null)
			comp.Skeleton = null;

		// Resolve graph
		if (state.Graph.Resolve(ResourceSystem, comp.GraphRef))
		{
			let res = state.Graph.Handle.Resource;
			comp.Graph = (res != null) ? res.Graph : null;
		}
		else if (!comp.GraphRef.IsValid && comp.Graph != null)
			comp.Graph = null;
	}

	private AnimGraphResolveState GetOrCreateResolveState(EntityHandle entity)
	{
		if (mResolveStates.TryGetValue(entity, let existing))
			return existing;
		let state = new AnimGraphResolveState();
		mResolveStates[entity] = state;
		return state;
	}

	public override void OnEntityDestroyed(EntityHandle entity)
	{
		if (mResolveStates.TryGetValue(entity, let state))
		{
			state.Release();
			delete state;
			mResolveStates.Remove(entity);
		}
		base.OnEntityDestroyed(entity);
	}
}

/// Per-component resource resolution tracking for animation graphs.
class AnimGraphResolveState
{
	public ResolvedResource<SkeletonResource> Skeleton;
	public ResolvedResource<AnimationGraphResource> Graph;

	public void Release()
	{
		Skeleton.Release();
		Graph.Release();
	}
}
