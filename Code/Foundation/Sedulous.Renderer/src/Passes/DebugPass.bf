namespace Sedulous.Renderer.Passes;

using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using Sedulous.Renderer;
using Sedulous.Renderer.Debug;
using Sedulous.DebugFont;
using Sedulous.Profiler;
using Sedulous.Materials;

/// Debug line drawing - uploads accumulated line vertices from
/// RenderContext.DebugDraw and renders them with depth test (occluded lines
/// still draw but behind opaque geometry). Runs after the main forward passes
/// and before post-processing so the lines compose into the HDR scene color.
class DebugPass : PipelinePass
{
	public override StringView Name => "DebugLines";

	public override void AddPasses(Sedulous.RenderGraph.RenderGraph graph, RenderView view, Pipeline pipeline)
	{
		// Check both pipeline-local (scene gizmos) and global (shared) debug draws
		let localDraw = pipeline.DebugDraw;
		let globalDraw = pipeline.RenderContext.DebugDraw;

		let localCount = (localDraw != null) ? localDraw.LineVertexCount + localDraw.OverlayLineVertexCount : 0;
		let globalCount = (globalDraw != null) ? globalDraw.LineVertexCount + globalDraw.OverlayLineVertexCount : 0;

		if (localCount == 0 && globalCount == 0)
			return;

		let outputHandle = graph.GetResource("PipelineOutput");
		if (!outputHandle.IsValid)
			return;

		let depthHandle = graph.GetResource("SceneDepth");
		let hasDepth = depthHandle.IsValid;

		graph.AddRenderPass("DebugLines", scope (builder) => {
			builder.SetColorTarget(0, outputHandle, .Load, .Store);
			if (hasDepth)
				builder.SetDepthTarget(depthHandle, .Load, .Store, 1.0f);
			builder
				.NeverCull()
				.SetExecute(new [=] (encoder) => {
					Execute(encoder, view, pipeline, hasDepth);
				});
		});
	}

	private void Execute(IRenderPassEncoder encoder, RenderView view, Pipeline pipeline, bool hasDepth)
	{
		using (Profiler.Begin("DebugLines"))
		{
		let renderContext = pipeline.RenderContext;
		let localDraw = pipeline.DebugDraw;
		let globalDraw = renderContext.DebugDraw;
		let debugSystem = renderContext.DebugDrawSystem;
		let cache = renderContext.PipelineStateCache;
		if (cache == null || debugSystem == null) return;

		// Merge depth-tested and overlay vertices from both local (per-pipeline)
		// and global (shared) debug draws into the vertex buffer.
		let localDepth = (localDraw != null) ? (uint32)localDraw.LineVertexCount : 0;
		let globalDepth = (globalDraw != null) ? (uint32)globalDraw.LineVertexCount : 0;
		let localOverlay = (localDraw != null) ? (uint32)localDraw.OverlayLineVertexCount : 0;
		let globalOverlay = (globalDraw != null) ? (uint32)globalDraw.OverlayLineVertexCount : 0;

		let totalDepth = localDepth + globalDepth;
		let totalOverlay = localOverlay + globalOverlay;
		if (totalDepth == 0 && totalOverlay == 0) return;

		let maxVerts = DebugDrawSystem.MaxLineVertices;
		let depthClamped = Math.Min(totalDepth, maxVerts);
		let overlayMax = maxVerts - depthClamped;
		let overlayClamped = Math.Min(totalOverlay, overlayMax);

		let vb = pipeline.GetLineVertexBuffer(view.FrameIndex);
		uint64 offset = 0;

		// Upload depth-tested lines: local first, then global
		if (localDepth > 0)
		{
			let count = Math.Min(localDepth, depthClamped);
			TransferHelper.WriteMappedBuffer(vb, offset,
				Span<uint8>((uint8*)localDraw.LineVertices.Ptr, (int)(count * DebugVertex.SizeInBytes)));
			offset += (uint64)(count * DebugVertex.SizeInBytes);
		}
		if (globalDepth > 0 && offset / DebugVertex.SizeInBytes < depthClamped)
		{
			let remaining = depthClamped - (uint32)(offset / DebugVertex.SizeInBytes);
			let count = Math.Min(globalDepth, remaining);
			TransferHelper.WriteMappedBuffer(vb, offset,
				Span<uint8>((uint8*)globalDraw.LineVertices.Ptr, (int)(count * DebugVertex.SizeInBytes)));
			offset += (uint64)(count * DebugVertex.SizeInBytes);
		}

		// Upload overlay lines: local first, then global
		let overlayStart = offset;
		if (localOverlay > 0)
		{
			let count = Math.Min(localOverlay, overlayClamped);
			TransferHelper.WriteMappedBuffer(vb, offset,
				Span<uint8>((uint8*)localDraw.OverlayLineVertices.Ptr, (int)(count * DebugVertex.SizeInBytes)));
			offset += (uint64)(count * DebugVertex.SizeInBytes);
		}
		if (globalOverlay > 0 && (uint32)((offset - overlayStart) / (uint64)DebugVertex.SizeInBytes) < overlayClamped)
		{
			let remaining = overlayClamped - (uint32)((offset - overlayStart) / (uint64)DebugVertex.SizeInBytes);
			let count = Math.Min(globalOverlay, remaining);
			TransferHelper.WriteMappedBuffer(vb, offset,
				Span<uint8>((uint8*)globalDraw.OverlayLineVertices.Ptr, (int)(count * DebugVertex.SizeInBytes)));
		}

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissor(0, 0, view.Width, view.Height);

		// Pipeline state - line list, depth test, no cull, alpha blend.
		var config = PipelineConfig();
		config.ShaderName = "debug_line";
		config.BlendMode = .AlphaBlend;
		config.CullMode = .None;
		config.ColorTargetCount = 1;
		config.Topology = .LineList;
		if (hasDepth)
		{
			config.DepthMode = .ReadOnly;
			config.DepthCompare = .LessEqual;
			config.DepthFormat = .Depth24PlusStencil8;
		}
		else
		{
			config.DepthMode = .Disabled;
		}

		// Vertex layout for DebugVertex.
		VertexAttribute[2] attrs = .(
			.(.Float32x3, 0, 0),      // Position
			.(.Unorm8x4, 12, 1)        // Color (packed RGBA8)
		);
		VertexBufferLayout vertexLayout = .((uint32)DebugVertex.SizeInBytes, .(&attrs[0], 2));
		VertexBufferLayout[1] vertexBuffers = .(vertexLayout);

		let frame = pipeline.GetFrameResources(view.FrameIndex);

		// Depth-tested lines
		if (depthClamped > 0)
		{
			let pipelineResult = cache.GetPipeline(config, vertexBuffers, null, pipeline.OutputFormat,
				hasDepth ? .Depth24PlusStencil8 : .Undefined);
			if (pipelineResult case .Ok(let depthPipeline))
			{
				encoder.SetPipeline(depthPipeline);
				encoder.SetVertexBuffer(0, vb, 0);
				pipeline.BindFrameGroup(encoder, frame);
				if (renderContext.DefaultMaterialBindGroup != null)
					encoder.SetBindGroup(BindGroupFrequency.Material, renderContext.DefaultMaterialBindGroup, default);
				if (frame.DrawCallBindGroup != null)
				{
					uint32[1] zeroOffset = .(0);
					encoder.SetBindGroup(BindGroupFrequency.DrawCall, frame.DrawCallBindGroup, zeroOffset);
				}
				encoder.Draw(depthClamped, 1, 0, 0);
			}
		}

		// Overlay lines (no depth test)
		if (overlayClamped > 0)
		{
			var overlayConfig = config;
			overlayConfig.DepthMode = .Disabled;

			let overlayPipelineResult = cache.GetPipeline(overlayConfig, vertexBuffers, null, pipeline.OutputFormat,
				hasDepth ? .Depth24PlusStencil8 : .Undefined);
			if (overlayPipelineResult case .Ok(let overlayPipeline))
			{
				encoder.SetPipeline(overlayPipeline);
				encoder.SetVertexBuffer(0, vb, 0);
				pipeline.BindFrameGroup(encoder, frame);
				if (renderContext.DefaultMaterialBindGroup != null)
					encoder.SetBindGroup(BindGroupFrequency.Material, renderContext.DefaultMaterialBindGroup, default);
				if (frame.DrawCallBindGroup != null)
				{
					uint32[1] zeroOff = .(0);
					encoder.SetBindGroup(BindGroupFrequency.DrawCall, frame.DrawCallBindGroup, zeroOff);
				}
				encoder.Draw((uint32)overlayClamped, 1, depthClamped, 0);
			}
		}

		} // scope
	}
}
