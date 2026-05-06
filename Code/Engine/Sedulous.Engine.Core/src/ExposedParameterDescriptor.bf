namespace Sedulous.Engine.Core;

using System;

/// Describes a single property exposed by a prefab for per-instance overriding.
/// Stored in the .prefab file alongside the entity subgraph.
class ExposedParameterDescriptor
{
	/// Display name shown in the inspector (e.g., "Health", "MeshRef").
	public String Name = new .() ~ delete _;

	/// The entity within the prefab that owns the component.
	public Guid EntityId;

	/// Serialization type ID of the component (e.g., "Sedulous.MeshComponent").
	public String ComponentTypeId = new .() ~ delete _;

	/// Property field name on the component (e.g., "MeshRef", "MaxHealth").
	public String PropertyName = new .() ~ delete _;
}
