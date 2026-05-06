namespace Sedulous.Engine.Core.Resources;

using System;
using System.Collections;
using Sedulous.Engine.Core;
using Sedulous.Serialization;
using Sedulous.Resources;
using static Sedulous.Resources.ResourceSerializerExtensions;
using Sedulous.Core.Mathematics;

/// Serializes and deserializes prefabs. Reuses the same entity/component
/// format as SceneSerializer with an additional ExposedParameters section.
/// No module-level data (prefabs are entity subgraphs, not full scenes).
class PrefabSerializer
{
	private ComponentTypeRegistry mTypeRegistry;

	public this(ComponentTypeRegistry typeRegistry)
	{
		mTypeRegistry = typeRegistry;
	}

	/// Serializes a prefab (scene entities + exposed parameters) to a serializer.
	public SerializationResult Save(Scene scene, List<ExposedParameterDescriptor> parameters, Serializer serializer)
	{
		// Exposed parameters
		var paramCount = (int32)parameters.Count;
		serializer.BeginArray("ExposedParameters", ref paramCount);

		for (let param in parameters)
		{
			serializer.BeginObject("");
			serializer.String("Name", param.Name);
			var entityId = param.EntityId;
			serializer.Guid("EntityId", ref entityId);
			serializer.String("ComponentType", param.ComponentTypeId);
			serializer.String("Property", param.PropertyName);
			serializer.EndObject();
		}

		serializer.EndArray();

		// Entities - same format as SceneSerializer
		let entities = scope List<EntityHandle>();
		for (let entity in scene.Entities)
			entities.Add(entity);

		let serializableModules = scope List<SceneModule>();
		for (let module in scene.Modules)
		{
			if (module.IsSerializable)
				serializableModules.Add(module);
		}

		var entityCount = (int32)entities.Count;
		serializer.BeginArray("Entities", ref entityCount);

		for (let entity in entities)
		{
			serializer.BeginObject("");

			var id = scene.GetEntityId(entity);
			serializer.Guid("Id", ref id);

			let nameView = scene.GetEntityName(entity);
			let name = scope String(nameView);
			serializer.String("Name", name);

			var active = scene.IsActive(entity);
			serializer.Bool("Active", ref active);

			let parentHandle = scene.GetParent(entity);
			var parentId = parentHandle.IsAssigned ? scene.GetEntityId(parentHandle) : Guid.Empty;
			serializer.Guid("Parent", ref parentId);

			var transform = scene.GetLocalTransform(entity);
			SerializeTransform(serializer, ref transform);

			// Components
			var componentCount = (int32)0;
			for (let module in serializableModules)
			{
				if (let cms = module as IComponentManagerSerializer)
				{
					if (cms.HasComponentForEntity(entity))
						componentCount++;
				}
			}

			serializer.BeginArray("Components", ref componentCount);

			for (let module in serializableModules)
			{
				if (let cms = module as IComponentManagerSerializer)
				{
					if (!cms.HasComponentForEntity(entity))
						continue;

					serializer.BeginObject("");
					let typeId = scope String(module.SerializationTypeId);
					serializer.String("TypeId", typeId);
					var version = cms.GetSerializationVersion();
					serializer.Int32("Version", ref version);

					serializer.BeginObject("Data");
					let adapter = scope ComponentSerializerAdapter(serializer, version);
					cms.SerializeEntityComponent(entity, adapter);
					serializer.EndObject();

					serializer.EndObject();
				}
			}

			serializer.EndArray();
			serializer.EndObject();
		}

		serializer.EndArray();
		return .Ok;
	}

	/// Deserializes a prefab into a scene (entities + parameters).
	public SerializationResult Load(Scene scene, List<ExposedParameterDescriptor> parameters, Serializer serializer)
	{
		// Load exposed parameters
		LoadParameters(parameters, serializer);

		// Load entities - same pattern as SceneSerializer.Load
		var entityCount = (int32)0;
		serializer.BeginArray("Entities", ref entityCount);

		let parentMap = scope Dictionary<Guid, Guid>();

		for (int32 i = 0; i < entityCount; i++)
		{
			serializer.BeginObject("");

			var id = Guid.Empty;
			serializer.Guid("Id", ref id);

			let name = scope String();
			serializer.String("Name", name);

			var active = true;
			serializer.Bool("Active", ref active);

			var parentId = Guid.Empty;
			serializer.Guid("Parent", ref parentId);

			var transform = Transform.Identity;
			SerializeTransform(serializer, ref transform);

			let entity = scene.CreateEntity(id, name);
			scene.SetActive(entity, active);
			scene.SetLocalTransform(entity, transform);

			if (parentId != .Empty)
				parentMap[id] = parentId;

			// Components
			var componentCount = (int32)0;
			serializer.BeginArray("Components", ref componentCount);

			for (int32 c = 0; c < componentCount; c++)
			{
				serializer.BeginObject("");

				let typeId = scope String();
				serializer.String("TypeId", typeId);

				var version = (int32)1;
				serializer.Int32("Version", ref version);

				SceneModule module = FindModuleByTypeId(scene, typeId);
				if (module == null && mTypeRegistry != null)
				{
					module = mTypeRegistry.CreateManager(typeId);
					if (module != null)
						scene.AddModule(module);
				}

				if (serializer.BeginObject("Data") == .Ok)
				{
					if (module != null)
					{
						if (let cms = module as IComponentManagerSerializer)
						{
							let adapter = scope ComponentSerializerAdapter(serializer, version);
							cms.DeserializeEntityComponent(entity, adapter);
						}
					}
					serializer.EndObject();
				}

				serializer.EndObject();
			}

			serializer.EndArray();
			serializer.EndObject();
		}

		serializer.EndArray();

		// Resolve parent-child relationships
		for (let kv in parentMap)
		{
			let childHandle = scene.FindEntity(kv.key);
			let parentHandle = scene.FindEntity(kv.value);
			if (childHandle.IsAssigned && parentHandle.IsAssigned)
				scene.SetParent(childHandle, parentHandle);
		}

		return .Ok;
	}

	/// Loads only the ExposedParameters section (for resource metadata without
	/// instantiating entities). Used when loading PrefabResource without a Scene.
	public SerializationResult LoadParametersOnly(List<ExposedParameterDescriptor> parameters, Serializer serializer)
	{
		LoadParameters(parameters, serializer);
		// Skip entity data - not needed for metadata-only load
		return .Ok;
	}

	/// Instantiates a prefab's entities into an existing scene under a parent entity.
	/// Returns a map from prefab entity GUIDs to live entity handles.
	/// Used by PrefabReferenceComponent during runtime instantiation.
	public Result<Dictionary<Guid, EntityHandle>> Instantiate(
		Scene scene, EntityHandle parentEntity,
		Serializer serializer, List<ExposedParameterDescriptor> parameters)
	{
		// Skip parameters section (already loaded on PrefabResource)
		let skipParams = new List<ExposedParameterDescriptor>();
		LoadParameters(skipParams, serializer);
		DeleteContainerAndItems!(skipParams);

		let guidMap = new Dictionary<Guid, EntityHandle>();
		let parentMap = scope Dictionary<Guid, Guid>();

		var entityCount = (int32)0;
		serializer.BeginArray("Entities", ref entityCount);

		for (int32 i = 0; i < entityCount; i++)
		{
			serializer.BeginObject("");

			var sourceId = Guid.Empty;
			serializer.Guid("Id", ref sourceId);

			let name = scope String();
			serializer.String("Name", name);

			var active = true;
			serializer.Bool("Active", ref active);

			var sourceParentId = Guid.Empty;
			serializer.Guid("Parent", ref sourceParentId);

			var transform = Transform.Identity;
			SerializeTransform(serializer, ref transform);

			// Create with a NEW guid (not the prefab's guid)
			let entity = scene.CreateEntity(name);
			scene.SetActive(entity, active);
			scene.SetLocalTransform(entity, transform);
			guidMap[sourceId] = entity;

			if (sourceParentId != .Empty)
				parentMap[sourceId] = sourceParentId;

			// Components
			var componentCount = (int32)0;
			serializer.BeginArray("Components", ref componentCount);

			for (int32 c = 0; c < componentCount; c++)
			{
				serializer.BeginObject("");

				let typeId = scope String();
				serializer.String("TypeId", typeId);

				var version = (int32)1;
				serializer.Int32("Version", ref version);

				SceneModule module = FindModuleByTypeId(scene, typeId);
				if (module == null && mTypeRegistry != null)
				{
					module = mTypeRegistry.CreateManager(typeId);
					if (module != null)
						scene.AddModule(module);
				}

				if (serializer.BeginObject("Data") == .Ok)
				{
					if (module != null)
					{
						if (let cms = module as IComponentManagerSerializer)
						{
							let adapter = scope ComponentSerializerAdapter(serializer, version);
							cms.DeserializeEntityComponent(entity, adapter);
						}
					}
					serializer.EndObject();
				}

				serializer.EndObject();
			}

			serializer.EndArray();
			serializer.EndObject();
		}

		serializer.EndArray();

		// Resolve parent-child: root entities -> parentEntity, others -> mapped parent
		for (let kv in guidMap)
		{
			let sourceId = kv.key;
			let liveHandle = kv.value;

			if (parentMap.TryGetValue(sourceId, let sourceParentId))
			{
				// Has a parent within the prefab
				if (guidMap.TryGetValue(sourceParentId, let liveParent))
					scene.SetParent(liveHandle, liveParent);
			}
			else
			{
				// Root entity - parent to the reference entity
				scene.SetParent(liveHandle, parentEntity);
			}
		}

		return .Ok(guidMap);
	}

	// === Helpers ===

	private void LoadParameters(List<ExposedParameterDescriptor> parameters, Serializer serializer)
	{
		var paramCount = (int32)0;
		serializer.BeginArray("ExposedParameters", ref paramCount);

		for (int32 i = 0; i < paramCount; i++)
		{
			serializer.BeginObject("");

			let param = new ExposedParameterDescriptor();

			serializer.String("Name", param.Name);
			serializer.Guid("EntityId", ref param.EntityId);
			serializer.String("ComponentType", param.ComponentTypeId);
			serializer.String("Property", param.PropertyName);

			parameters.Add(param);
			serializer.EndObject();
		}

		serializer.EndArray();
	}

	private SceneModule FindModuleByTypeId(Scene scene, StringView typeId)
	{
		for (let module in scene.Modules)
		{
			if (module.SerializationTypeId == typeId)
				return module;
		}
		return null;
	}

	private void SerializeTransform(Serializer serializer, ref Transform transform)
	{
		serializer.Float("PosX", ref transform.Position.X);
		serializer.Float("PosY", ref transform.Position.Y);
		serializer.Float("PosZ", ref transform.Position.Z);
		serializer.Float("RotX", ref transform.Rotation.X);
		serializer.Float("RotY", ref transform.Rotation.Y);
		serializer.Float("RotZ", ref transform.Rotation.Z);
		serializer.Float("RotW", ref transform.Rotation.W);
		serializer.Float("ScaleX", ref transform.Scale.X);
		serializer.Float("ScaleY", ref transform.Scale.Y);
		serializer.Float("ScaleZ", ref transform.Scale.Z);
	}
}
