namespace Sedulous.Engine.Core;

using System;

/// Non-generic base class for component managers.
/// Provides the InitializePendingComponents hook that Scene calls
/// before FixedUpdate each frame. Only component managers need this -
/// plain SceneModules do not.
public abstract class ComponentManagerBase : SceneModule
{
	/// Initializes any components created since the last frame.
	/// Called by Scene before FixedUpdate so new physics bodies, audio sources,
	/// etc. are ready before their first simulation step.
	/// ComponentManager<T> overrides this to call OnComponentInitialized on
	/// each pending component.
	public abstract void InitializePendingComponents();

	/// Whether the given entity has a component managed by this manager.
	public abstract bool HasComponent(EntityHandle entity);

	/// Gets the component for the given entity, or null. Non-generic accessor.
	public abstract Component GetComponent(EntityHandle entity);

	/// Creates a component on the given entity. Non-generic accessor for editor use.
	/// Returns the created component, or null on failure.
	public abstract Component CreateComponentOnEntity(EntityHandle entity);

	/// Destroys the component on the given entity. Non-generic accessor for editor use.
	public abstract void DestroyComponentOnEntity(EntityHandle entity);

	/// Human-readable display name for this component type (e.g. "Mesh", "Light").
	/// Default: type name of the managed component class.
	public abstract void GetComponentDisplayName(String outName);
}
