namespace Sedulous.Editor.App;

using System;
using System.IO;
using Sedulous.Editor.Core;
using Sedulous.Engine.Core;
using Sedulous.Engine.Core.Resources;

/// Creates an empty prefab asset.
class PrefabAssetCreator : IAssetCreator
{
	public StringView DisplayName => "Prefab";
	public StringView Category => "Core";
	public StringView Extension => ".prefab";

	public Result<Guid> Create(StringView path, EditorContext context)
	{
		let provider = context.ResourceSystem?.SerializerProvider;
		if (provider == null)
			return .Err;

		// Create an empty scene (prefabs are entity subgraphs serialized like scenes)
		let scene = new Scene();
		scene.Name.Set("New Prefab");
		defer delete scene;

		let prefabRes = new PrefabResource();
		defer delete prefabRes;

		prefabRes.Scene = scene;

		let stream = scope FileStream();
		if (stream.Create(path, .Write) case .Err)
			return .Err;
		if (prefabRes.WriteToStream(stream, provider) case .Err)
			return .Err;

		return .Ok(prefabRes.Id);
	}
}
