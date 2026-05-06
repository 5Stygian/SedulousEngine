namespace Sedulous.Engine.Core.Resources;

using System;
using System.Collections;
using Sedulous.Resources;
using Sedulous.Serialization;
using Sedulous.Engine.Core;

/// A loadable prefab asset - a serialized entity subgraph with exposed
/// parameter descriptors. Entities are serialized in the same format as
/// scenes (via PrefabSerializer) and instantiated into live scenes by
/// PrefabReferenceComponent.
class PrefabResource : Resource
{
	/// Live scene for editing (set for saving, null for read-only use).
	/// When opening a .prefab in the editor, a temporary Scene is created
	/// and entities are loaded into it. When saving, the scene is serialized back.
	public Scene Scene;

	/// Type registry for component deserialization (not owned).
	public ComponentTypeRegistry TypeRegistry;

	/// Exposed parameters that can be overridden per instance.
	/// Loaded from the .prefab file; edited in the prefab editor.
	public List<ExposedParameterDescriptor> ExposedParameters = new .() ~ DeleteContainerAndItems!(_);

	public override ResourceType ResourceType => .("Sedulous.Engine.Core.Resources.PrefabResource");

	public override int32 SerializationVersion => 1;

	protected override SerializationResult OnSerialize(Serializer serializer)
	{
		let prefabSerializer = scope PrefabSerializer(TypeRegistry);

		if (serializer.IsWriting)
			return prefabSerializer.Save(Scene, ExposedParameters, serializer);
		else
		{
			if (Scene != null)
				return prefabSerializer.Load(Scene, ExposedParameters, serializer);
			else
				return prefabSerializer.LoadParametersOnly(ExposedParameters, serializer);
		}
	}
}
