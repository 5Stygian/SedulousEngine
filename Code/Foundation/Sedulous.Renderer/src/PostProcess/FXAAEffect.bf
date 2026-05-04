namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using Sedulous.Shaders;
using Sedulous.Profiler;

/// Fast Approximate Anti-Aliasing (FXAA 3.11 quality variant).
/// Spatial anti-aliasing operating on LDR color - runs after tone mapping.
/// Single fullscreen pass with luminance-based edge detection and directional search.
class FXAAEffect : PostProcessEffect
{
	private Sedulous.RHI.IRenderPipeline mPipeline;
	private IPipelineLayout mPipelineLayout;
	private IBindGroupLayout mBindGroupLayout;
	private ISampler mSampler;
	private IBuffer mParamsBuffer;
	private IDevice mDevice;
	private RenderContext mRenderContext;

	// Per-frame bind groups (double-buffered to avoid use-after-free)
	private const int MaxFrames = 2;
	private IBindGroup[MaxFrames] mBindGroups;

	/// Sub-pixel quality factor. 0.0 = off, 0.75 = default, 1.0 = maximum smoothing.
	public float SubpixelQuality = 0.75f;

	/// Edge detection contrast threshold. Lower = more edges detected.
	/// 0.166 = default, 0.125 = sharper, 0.063 = overkill.
	public float EdgeThreshold = 0.166f;

	/// Minimum edge threshold. Avoids processing very dark areas where
	/// contrast is low but visually insignificant.
	public float EdgeThresholdMin = 0.0312f;

	public override StringView Name => "FXAA";

	public override Result<void> OnInitialize(RenderContext renderContext)
	{
		mRenderContext = renderContext;
		mDevice = renderContext.Device;
		let shaderSystem = renderContext.ShaderSystem;
		if (shaderSystem == null)
			return .Err;

		// Fullscreen triangle vertex shader (shared across post-process passes)
		let vertResult = shaderSystem.GetShader("fullscreen", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let vertModule = vertResult.Value;

		let fragResult = shaderSystem.GetShader("fxaa", .Fragment);
		if (fragResult case .Err)
			return .Err;
		let fragModule = fragResult.Value;

		// Bind group layout: b0 = params, t0 = scene color, s0 = linear sampler
		BindGroupLayoutEntry[3] entries = .(
			.UniformBuffer(0, .Fragment),
			.SampledTexture(0, .Fragment),
			.Sampler(0, .Fragment)
		);

		BindGroupLayoutDesc layoutDesc = .() { Label = "FXAA BindGroup Layout", Entries = entries };
		if (mDevice.CreateBindGroupLayout(layoutDesc) case .Ok(let layout))
			mBindGroupLayout = layout;
		else
			return .Err;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		if (mDevice.CreatePipelineLayout(.(layouts)) case .Ok(let plLayout))
			mPipelineLayout = plLayout;
		else
			return .Err;

		// Linear sampler for offset sampling
		SamplerDesc samplerDesc = .()
		{
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Nearest,
			AddressU = .ClampToEdge,
			AddressV = .ClampToEdge,
			AddressW = .ClampToEdge
		};
		if (mDevice.CreateSampler(samplerDesc) case .Ok(let sampler))
			mSampler = sampler;
		else
			return .Err;

		// Params constant buffer
		BufferDesc bufDesc = .()
		{
			Label = "FXAA Params",
			Size = FXAAParams.Size,
			Usage = .Uniform,
			Memory = .CpuToGpu
		};
		if (mDevice.CreateBuffer(bufDesc) case .Ok(let buf))
			mParamsBuffer = buf;
		else
			return .Err;

		// Render pipeline (fullscreen triangle, no vertex buffers)
		// Output format matches pipeline output - FXAA runs after tonemap on LDR
		// but the pipeline output is still RGBA16Float (the blit handles final format).
		ColorTargetState[1] colorTargets = .(.() { Format = .RGBA16Float });

		RenderPipelineDesc pipelineDesc = .()
		{
			Label = "FXAA Pipeline",
			Layout = mPipelineLayout,
			Vertex = .() { Shader = .(vertModule.Module, "main"), Buffers = default },
			Fragment = .() { Shader = .(fragModule.Module, "main"), Targets = colorTargets },
			Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
			DepthStencil = null,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (mDevice.CreateRenderPipeline(pipelineDesc) case .Ok(let pipe))
			mPipeline = pipe;
		else
			return .Err;

		return .Ok;
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderContext renderContext, PostProcessContext ctx)
	{
		using (Profiler.Begin("FXAA"))
		{

		// Upload params
		FXAAParams @params = .()
		{
			TexelSizeX = 1.0f / Math.Max(view.Width, 1),
			TexelSizeY = 1.0f / Math.Max(view.Height, 1),
			SubpixelQuality = SubpixelQuality,
			EdgeThreshold = EdgeThreshold,
			EdgeThresholdMin = EdgeThresholdMin
		};
		TransferHelper.WriteMappedBuffer(mParamsBuffer, 0, Span<uint8>((uint8*)&@params, FXAAParams.Size));

		let input = ctx.Input;
		let output = ctx.Output;

		graph.AddRenderPass("FXAA", scope (builder) => {
			builder
				.ReadTexture(input)
				.SetColorTarget(0, output, .DontCare, .Store)
				.NeverCull()
				.SetExecute(new [=] (encoder) => {
					ExecuteFXAA(encoder, view, graph, input);
				});
		});

		} // FXAA profiler scope
	}

	private void ExecuteFXAA(IRenderPassEncoder encoder, RenderView view, RenderGraph graph, RGHandle inputHandle)
	{
		let inputView = graph.GetTextureView(inputHandle);
		if (inputView == null)
			return;

		let frameSlot = view.FrameIndex % MaxFrames;

		// Destroy previous bind group for this frame slot
		if (mBindGroups[frameSlot] != null)
			mDevice.DestroyBindGroup(ref mBindGroups[frameSlot]);

		BindGroupEntry[3] bgEntries = .(
			BindGroupEntry.Buffer(mParamsBuffer, 0, FXAAParams.Size),
			BindGroupEntry.Texture(inputView),
			BindGroupEntry.Sampler(mSampler)
		);

		BindGroupDesc bgDesc = .() { Label = "FXAA BindGroup", Layout = mBindGroupLayout, Entries = bgEntries };
		if (mDevice.CreateBindGroup(bgDesc) case .Ok(let bg))
			mBindGroups[frameSlot] = bg;

		if (mBindGroups[frameSlot] == null)
			return;

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0, 1);
		encoder.SetScissor(0, 0, view.Width, view.Height);
		encoder.SetPipeline(mPipeline);
		encoder.SetBindGroup(0, mBindGroups[frameSlot], default);
		encoder.Draw(3, 1, 0, 0);
	}

	public override void OnShutdown()
	{
		if (mDevice == null) return;

		for (int i = 0; i < MaxFrames; i++)
			if (mBindGroups[i] != null)
				mDevice.DestroyBindGroup(ref mBindGroups[i]);

		if (mPipeline != null) mDevice.DestroyRenderPipeline(ref mPipeline);
		if (mPipelineLayout != null) mDevice.DestroyPipelineLayout(ref mPipelineLayout);
		if (mBindGroupLayout != null) mDevice.DestroyBindGroupLayout(ref mBindGroupLayout);
		if (mSampler != null) mDevice.DestroySampler(ref mSampler);
		if (mParamsBuffer != null) mDevice.DestroyBuffer(ref mParamsBuffer);
	}

	[CRepr]
	private struct FXAAParams
	{
		public float TexelSizeX;
		public float TexelSizeY;
		public float SubpixelQuality;
		public float EdgeThreshold;
		public float EdgeThresholdMin;
		public float _Pad0;
		public float _Pad1;
		public float _Pad2;
		public const uint64 Size = 32;
	}
}
