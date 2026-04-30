namespace TowerDefense;

using System;
using Sedulous.Engine.Core;
using Sedulous.Engine.Render;
using Sedulous.Core.Mathematics;
using Sedulous.Resources;
using Sedulous.Messaging;
using Sedulous.Shell.Input;
using Sedulous.Renderer.Debug;

/// Handles tower placement: mouse ray to grid, validation, building.
/// Draws debug markers on tower slots and shows a preview tower at the cursor.
class TowerPlacement
{
	/// Currently selected tower type for placement. null = nothing selected.
	public TowerType? SelectedType;

	/// Hover grid position (valid when mouse is over a valid cell).
	public int32 HoverX;
	public int32 HoverZ;
	public bool HoverValid;

	// Preview entity - follows the mouse cursor when a tower is selected
	private EntityHandle mPreviewBase = .Invalid;
	private EntityHandle mPreviewWeapon = .Invalid;
	private TowerType? mPreviewType;

	/// Places a tower or updates hover. Call each frame from OnUpdate.
	public void Update(
		IMouse mouse, Scene scene, GameSubsystem gameSub,
		TowerComponentManager towerMgr, ModelRegistry models,
		ResourceSystem resources, EntityHandle cameraEntity)
	{
		HoverValid = false;

		// Right click cancels tower selection
		if (mouse.IsButtonPressed(.Right) && SelectedType != null)
		{
			SelectedType = null;
			Console.WriteLine("[Input] Tower selection cancelled");
		}

		if (SelectedType == null || scene == null || gameSub.Phase != .Playing)
		{
			HidePreview(scene);
			return;
		}

		// Get camera matrices for unprojection
		let cameraMgr = scene.GetModule<CameraComponentManager>();
		if (cameraMgr == null)
			return;

		let camComp = cameraMgr.GetForEntity(cameraEntity);
		if (camComp == null)
			return;

		let renderSub = gameSub.Context.GetSubsystem<RenderSubsystem>();
		if (renderSub == null)
			return;

		let pipeline = renderSub.GetPipeline(scene);
		if (pipeline == null)
			return;

		let viewMatrix = camComp.GetViewMatrix(scene);
		let aspect = (float)pipeline.OutputWidth / (float)pipeline.OutputHeight;
		let projMatrix = camComp.GetProjectionMatrix(aspect);
		let viewProj = viewMatrix * projMatrix;

		// Unproject mouse position to ray
		let ndcX = (2.0f * mouse.X / (float)pipeline.OutputWidth) - 1.0f;
		let ndcY = 1.0f - (2.0f * mouse.Y / (float)pipeline.OutputHeight);

		Matrix invVP = .Identity;
		if (!Matrix.TryInvert(viewProj, out invVP))
			return;

		var nearWorld = Vector4.Transform(Vector4(ndcX, ndcY, 0, 1), invVP);
		var farWorld = Vector4.Transform(Vector4(ndcX, ndcY, 1, 1), invVP);

		if (Math.Abs(nearWorld.W) < 0.0001f || Math.Abs(farWorld.W) < 0.0001f)
			return;

		let nearPos = Vector3(nearWorld.X, nearWorld.Y, nearWorld.Z) / nearWorld.W;
		let farPos = Vector3(farWorld.X, farWorld.Y, farWorld.Z) / farWorld.W;
		let rayDir = farPos - nearPos;

		// Intersect with Y=0 plane
		if (Math.Abs(rayDir.Y) < 0.001f)
			return;

		let t = -nearPos.Y / rayDir.Y;
		if (t < 0)
			return;

		let hitPos = nearPos + rayDir * t;

		// Convert to grid
		int32 gx, gz;
		if (!gameSub.Map.CurrentMap.WorldToGrid(hitPos, out gx, out gz))
		{
			HidePreview(scene);
			return;
		}

		HoverX = gx;
		HoverZ = gz;
		HoverValid = gameSub.Map.CanPlaceTower(gx, gz);

		// Update preview entity position
		let worldPos = gameSub.Map.CurrentMap.GridToWorld(gx, gz);
		UpdatePreview(scene, models, resources, worldPos);

		// Place on left click
		if (mouse.IsButtonPressed(.Left) && HoverValid)
		{
			let towerType = SelectedType.Value;
			let stats = TowerStats.Get(towerType);
			let cost = stats.Levels[0].Cost;

			if (gameSub.SpendGold(cost))
			{
				let entity = BuildTower(scene, towerMgr, models, resources, gameSub, towerType, gx, gz);

				if (entity != .Invalid)
				{
					gameSub.Map.OccupyCell(gx, gz);

					if (gameSub.[Friend]mBus != null)
					{
						TowerPlacedMsg msg = .()
						{
							EntityId = entity,
							Type = towerType,
							GridX = gx,
							GridZ = gz
						};
						gameSub.[Friend]mBus.Queue<TowerPlacedMsg>(msg);
					}

					Console.WriteLine("[Tower] Placed {} at ({}, {}), cost {}", towerType, gx, gz, cost);
				}
			}
			else
			{
				Console.WriteLine("[Tower] Not enough gold for {} (need {}, have {})", towerType, cost, gameSub.Gold);
			}
		}
	}

	/// Draws a flat rectangle as overlay lines at a given Y height.
	private static void DrawFlatRectOverlay(DebugDraw dbg, Vector3 center, float half, float y, Color color)
	{
		let c0 = center + .(-half, y, -half);
		let c1 = center + .( half, y, -half);
		let c2 = center + .( half, y,  half);
		let c3 = center + .(-half, y,  half);
		dbg.DrawLineOverlay(c0, c1, color);
		dbg.DrawLineOverlay(c1, c2, color);
		dbg.DrawLineOverlay(c2, c3, color);
		dbg.DrawLineOverlay(c3, c0, color);
	}

	/// Draws debug markers on tower slots and hover cell. Only when placing.
	public void DrawDebug(DebugDraw dbg, GameSubsystem gameSub)
	{
		if (dbg == null || gameSub.Map.CurrentMap == null || SelectedType == null)
			return;

		let map = gameSub.Map.CurrentMap;
		let slotColor = Color(50, 200, 50, 255);     // green for available
		let occupiedColor = Color(150, 150, 150, 255); // gray for occupied
		let hoverValidColor = Color(50, 255, 50, 255); // bright green for valid hover
		let hoverInvalidColor = Color(255, 50, 50, 255); // red for invalid hover

		// Draw all tower slots
		for (int32 z = 0; z < map.Height; z++)
		{
			for (int32 x = 0; x < map.Width; x++)
			{
				if (map.GetCell(x, z) != .TowerSlot)
					continue;

				let pos = map.GridToWorld(x, z);
				let occupied = !gameSub.Map.CanPlaceTower(x, z);
				let color = occupied ? occupiedColor : slotColor;

				// Draw a flat wire rect as overlay (above mesh height)
				let half = MapData.TileSize * 0.45f;
				let y = 0.3f;
				DrawFlatRectOverlay(dbg, pos, half, y, color);
			}
		}

		// Draw hover highlight
		if (SelectedType != null)
		{
			let pos = gameSub.Map.CurrentMap.GridToWorld(HoverX, HoverZ);
			let color = HoverValid ? hoverValidColor : hoverInvalidColor;
			let half = MapData.TileSize * 0.48f;
			let y = 0.3f;
			DrawFlatRectOverlay(dbg, pos, half, y, color);

			// Draw range circle as overlay (renders on top, avoids clipping into meshes)
			if (HoverValid)
			{
				let stats = TowerStats.Get(SelectedType.Value);
				let range = stats.Levels[0].Range;
				let rangeColor = Color(255, 255, 100, 200);
				let segments = 48;
				let y = 0.3f; // above tile mesh height

				for (int i = 0; i < segments; i++)
				{
					let a0 = (float)i / (float)segments * Math.PI_f * 2.0f;
					let a1 = (float)(i + 1) / (float)segments * Math.PI_f * 2.0f;
					let p0 = pos + Vector3(Math.Cos(a0) * range, y, Math.Sin(a0) * range);
					let p1 = pos + Vector3(Math.Cos(a1) * range, y, Math.Sin(a1) * range);
					dbg.DrawLineOverlay(p0, p1, rangeColor);
				}
			}
		}
	}

	// ==================== Preview Entity ====================

	/// Creates or moves the preview tower entity at the cursor position.
	private void UpdatePreview(Scene scene, ModelRegistry models, ResourceSystem resources, Vector3 worldPos)
	{
		if (SelectedType == null)
		{
			HidePreview(scene);
			return;
		}

		// Recreate preview if tower type changed
		if (mPreviewType != SelectedType)
		{
			HidePreview(scene);
			CreatePreview(scene, models, resources);
			mPreviewType = SelectedType;
		}

		// Move preview to cursor position
		if (scene.IsValid(mPreviewBase))
		{
			var transform = Transform();
			transform.Position = worldPos;
			transform.Rotation = .Identity;
			transform.Scale = .One;
			scene.SetLocalTransform(mPreviewBase, transform);
		}
	}

	/// Creates the preview entity (base + weapon, no component).
	private void CreatePreview(Scene scene, ModelRegistry models, ResourceSystem resources)
	{
		if (SelectedType == null)
			return;

		let stats = TowerStats.Get(SelectedType.Value);

		// Create base preview entity
		mPreviewBase = scene.CreateEntity("TowerPreview");
		var transform = Transform();
		transform.Position = .Zero;
		transform.Rotation = .Identity;
		transform.Scale = .One;
		scene.SetLocalTransform(mPreviewBase, transform);

		let meshMgr = scene.GetModule<MeshComponentManager>();
		if (meshMgr != null)
		{
			let baseLoaded = models.LoadModel(stats.BaseModel, resources);
			if (baseLoaded != null)
			{
				let meshHandle = meshMgr.CreateComponent(mPreviewBase);
				if (let mesh = meshMgr.Get(meshHandle))
				{
					var meshRef = ResourceRef(baseLoaded.MeshResource.Id, baseLoaded.MeshResource.Name);
					defer meshRef.Dispose();
					mesh.SetMeshRef(meshRef);
					for (int32 slot = 0; slot < baseLoaded.MaterialRefs.Count; slot++)
						mesh.SetMaterialRef(slot, baseLoaded.MaterialRefs[slot]);
				}
			}
		}

		// Create weapon preview as child of base preview
		mPreviewWeapon = scene.CreateEntity("WeaponPreview");
		scene.SetParent(mPreviewWeapon, mPreviewBase);

		var weaponTransform = Transform();
		weaponTransform.Position = .(0, 0.5f, 0);
		weaponTransform.Rotation = .Identity;
		weaponTransform.Scale = .One;
		scene.SetLocalTransform(mPreviewWeapon, weaponTransform);

		if (meshMgr != null)
		{
			let weaponLoaded = models.LoadModel(stats.WeaponModel, resources);
			if (weaponLoaded != null)
			{
				let meshHandle = meshMgr.CreateComponent(mPreviewWeapon);
				if (let mesh = meshMgr.Get(meshHandle))
				{
					var meshRef = ResourceRef(weaponLoaded.MeshResource.Id, weaponLoaded.MeshResource.Name);
					defer meshRef.Dispose();
					mesh.SetMeshRef(meshRef);
					for (int32 slot = 0; slot < weaponLoaded.MaterialRefs.Count; slot++)
						mesh.SetMaterialRef(slot, weaponLoaded.MaterialRefs[slot]);
				}
			}
		}
	}

	/// Removes the preview entity.
	private void HidePreview(Scene scene)
	{
		if (scene != null && scene.IsValid(mPreviewBase))
			scene.DestroyEntity(mPreviewBase);

		mPreviewBase = .Invalid;
		mPreviewWeapon = .Invalid;
		mPreviewType = null;
	}

	// ==================== Tower Building ====================

	/// Creates the tower entity with base + weapon child entities.
	private EntityHandle BuildTower(Scene scene, TowerComponentManager towerMgr,
		ModelRegistry models, ResourceSystem resources, GameSubsystem gameSub,
		TowerType type, int32 gx, int32 gz)
	{
		let stats = TowerStats.Get(type);
		let levelStats = stats.Levels[0];
		let worldPos = gameSub.Map.CurrentMap.GridToWorld(gx, gz);

		// Create base entity
		let baseEntity = scene.CreateEntity("Tower");
		var transform = Transform();
		transform.Position = worldPos;
		transform.Rotation = .Identity;
		transform.Scale = .One;
		scene.SetLocalTransform(baseEntity, transform);

		// Attach base mesh
		let meshMgr = scene.GetModule<MeshComponentManager>();
		if (meshMgr != null)
		{
			let baseLoaded = models.LoadModel(stats.BaseModel, resources);
			if (baseLoaded != null)
			{
				let meshHandle = meshMgr.CreateComponent(baseEntity);
				if (let mesh = meshMgr.Get(meshHandle))
				{
					var meshRef = ResourceRef(baseLoaded.MeshResource.Id, baseLoaded.MeshResource.Name);
					defer meshRef.Dispose();
					mesh.SetMeshRef(meshRef);
					for (int32 slot = 0; slot < baseLoaded.MaterialRefs.Count; slot++)
						mesh.SetMaterialRef(slot, baseLoaded.MaterialRefs[slot]);
				}
			}
		}

		// Create weapon as child entity
		let weaponEntity = scene.CreateEntity("Weapon");
		scene.SetParent(weaponEntity, baseEntity);

		var weaponTransform = Transform();
		weaponTransform.Position = .(0, 0.5f, 0); // local offset above base
		weaponTransform.Rotation = .Identity;
		weaponTransform.Scale = .One;
		scene.SetLocalTransform(weaponEntity, weaponTransform);

		if (meshMgr != null)
		{
			let weaponLoaded = models.LoadModel(stats.WeaponModel, resources);
			if (weaponLoaded != null)
			{
				let meshHandle = meshMgr.CreateComponent(weaponEntity);
				if (let mesh = meshMgr.Get(meshHandle))
				{
					var meshRef = ResourceRef(weaponLoaded.MeshResource.Id, weaponLoaded.MeshResource.Name);
					defer meshRef.Dispose();
					mesh.SetMeshRef(meshRef);
					for (int32 slot = 0; slot < weaponLoaded.MaterialRefs.Count; slot++)
						mesh.SetMaterialRef(slot, weaponLoaded.MaterialRefs[slot]);
				}
			}
		}

		// Attach tower component
		let compHandle = towerMgr.CreateComponent(baseEntity);
		if (let comp = towerMgr.Get(compHandle))
		{
			comp.Type = type;
			comp.Level = 1;
			comp.Damage = levelStats.Damage;
			comp.Range = levelStats.Range;
			comp.FireRate = levelStats.FireRate;
			comp.FireCooldown = 0;
			comp.GridX = gx;
			comp.GridZ = gz;
			comp.WeaponEntity = weaponEntity;
		}

		return baseEntity;
	}
}
