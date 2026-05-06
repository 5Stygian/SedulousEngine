namespace Sedulous.Engine.Core;

using System;

/// Lightweight tag component added to every entity created by prefab
/// instantiation. Enables override targeting and re-instantiation mapping.
///
/// Not serialized - recreated each time the prefab instantiates.
class PrefabInstanceTag : Component
{
	/// GUID of the PrefabResource that created this entity.
	public Guid PrefabId;

	/// The entity's original GUID within the .prefab file.
	/// Used to map overrides to the correct instantiated entity.
	public Guid SourceEntityId;

	/// The entity that holds the PrefabReferenceComponent (the "instance root").
	public EntityHandle ReferenceEntity = .Invalid;
}

/// Manages PrefabInstanceTag components. No update logic, just storage.
/// Empty SerializationTypeId opts out of serialization entirely -
/// tags are runtime-only, recreated on each prefab instantiation.
class PrefabInstanceTagManager : ComponentManager<PrefabInstanceTag>
{
	public override StringView SerializationTypeId => "";
}
