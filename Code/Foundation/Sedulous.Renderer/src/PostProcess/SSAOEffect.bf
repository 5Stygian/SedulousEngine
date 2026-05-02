namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using Sedulous.Shaders;
using Sedulous.Profiler;
using Sedulous.Core.Mathematics;

/// Screen-Space Ambient Occlusion effect.
/// Produces an "AOTexture" auxiliary texture that the tonemap shader reads
/// to darken occluded areas. Does not modify the color chain directly —
/// passes ctx.Input through to ctx.Output unchanged.
///
/// Two-pass: SSAO generation (depth + normals → AO) is done here.
/// The AO texture is applied by TonemapEffect as a multiply on scene color.
class SSAOEffect : PostProcessEffect
{
	// Generate pass
	private Sedulous.RHI.IRenderPipeline mPipeline;
	private IPipelineLayout mPipelineLayout;
	private IBindGroupLayout mBindGroupLayout;

	// Blur pass
	private Sedulous.RHI.IRenderPipeline mBlurPipeline;
	private IPipelineLayout mBlurPipelineLayout;
	private IBindGroupLayout mBlurBindGroupLayout;
	private IBuffer mBlurParamsBuffer;

	private ISampler mPointSampler;
	private IBuffer mParamsBuffer;
	private IBuffer mKernelBuffer;
	private IDevice mDevice;
	private RenderContext mRenderContext;

	// Per-frame bind groups (double-buffered)
	private const int MaxFrames = 2;
	private IBindGroup[MaxFrames] mBindGroups;
	private IBindGroup[MaxFrames] mBlurBindGroups;

	// Hemisphere kernel samples (generated once)
	private Vector4[16] mKernelSamples;

	/// World-space sampling radius.
	public float Radius = 0.5f;

	/// Occlusion intensity (applied as power curve).
	public float Intensity = 1.5f;

	/// Depth bias to prevent self-occlusion on flat surfaces.
	public float Bias = 0.025f;

	public override StringView Name => "SSAO";

	public override Result<void> OnInitialize(RenderContext renderContext)
	{
		mRenderContext = renderContext;
		mDevice = renderContext.Device;
		let shaderSystem = renderContext.ShaderSystem;
		if (shaderSystem == null)
			return .Err;

		// Generate hemisphere kernel
		GenerateKernel();

		let vertResult = shaderSystem.GetShader("fullscreen", .Vertex);
		if (vertResult case .Err) return .Err;
		let vertModule = vertResult.Value;

		let fragResult = shaderSystem.GetShader("ssao", .Fragment);
		if (fragResult case .Err) return .Err;
		let fragModule = fragResult.Value;

		// Bind group layout:
		// b0 = SSAOParams
		// b1 = SSAOKernel (16 x float4)
		// t0 = depth
		// t1 = normals
		// s0 = point sampler
		BindGroupLayoutEntry[5] entries = .(
			.UniformBuffer(0, .Fragment),
			.UniformBuffer(1, .Fragment),
			.SampledTexture(0, .Fragment),
			.SampledTexture(1, .Fragment),
			.Sampler(0, .Fragment)
		);

		BindGroupLayoutDesc layoutDesc = .() { Label = "SSAO BindGroup Layout", Entries = entries };
		if (mDevice.CreateBindGroupLayout(layoutDesc) case .Ok(let layout))
			mBindGroupLayout = layout;
		else
			return .Err;

		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		if (mDevice.CreatePipelineLayout(.(layouts)) case .Ok(let plLayout))
			mPipelineLayout = plLayout;
		else
			return .Err;

		// Point sampler (no interpolation for depth/normal reads)
		SamplerDesc samplerDesc = .()
		{
			MinFilter = .Nearest, MagFilter = .Nearest, MipmapFilter = .Nearest,
			AddressU = .ClampToEdge, AddressV = .ClampToEdge, AddressW = .ClampToEdge
		};
		if (mDevice.CreateSampler(samplerDesc) case .Ok(let sampler))
			mPointSampler = sampler;
		else
			return .Err;

		// Params buffer
		BufferDesc paramsBufDesc = .()
		{
			Label = "SSAO Params",
			Size = SSAOParams.Size,
			Usage = .Uniform,
			Memory = .CpuToGpu
		};
		if (mDevice.CreateBuffer(paramsBufDesc) case .Ok(let buf))
			mParamsBuffer = buf;
		else
			return .Err;

		// Kernel buffer (16 x float4 = 256 bytes)
		BufferDesc kernelBufDesc = .()
		{
			Label = "SSAO Kernel",
			Size = 256,
			Usage = .Uniform,
			Memory = .CpuToGpu
		};
		if (mDevice.CreateBuffer(kernelBufDesc) case .Ok(let kernelBuf))
			mKernelBuffer = kernelBuf;
		else
			return .Err;

		// Upload kernel samples
		TransferHelper.WriteMappedBuffer(mKernelBuffer, 0,
			Span<uint8>((uint8*)&mKernelSamples[0], 256));

		// Render pipeline — output is R8Unorm (single channel AO)
		ColorTargetState[1] colorTargets = .(.() { Format = .R8Unorm });

		RenderPipelineDesc pipelineDesc = .()
		{
			Label = "SSAO Pipeline",
			Layout = mPipelineLayout,
			Vertex = .() { Shader = .(vertModule.Module, "main"), Buffers = default },
			Fragment = .() { Shader = .(fragModule.Module, "main"), Targets = colorTargets },
			Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
			DepthStencil = null,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (mDevice.CreateRenderPipeline(pipelineDesc) case .Ok(let genPipe))
			mPipeline = genPipe;
		else
			return .Err;

		// === Blur pass ===
		let blurFragResult = shaderSystem.GetShader("ssao_blur", .Fragment);
		if (blurFragResult case .Err) return .Err;
		let blurFragModule = blurFragResult.Value;

		// Blur bind group: b0 = BlurParams, t0 = raw AO, t1 = depth, s0 = point sampler
		BindGroupLayoutEntry[4] blurEntries = .(
			.UniformBuffer(0, .Fragment),
			.SampledTexture(0, .Fragment),
			.SampledTexture(1, .Fragment),
			.Sampler(0, .Fragment)
		);

		BindGroupLayoutDesc blurLayoutDesc = .() { Label = "SSAO Blur BindGroup Layout", Entries = blurEntries };
		if (mDevice.CreateBindGroupLayout(blurLayoutDesc) case .Ok(let blurLayout))
			mBlurBindGroupLayout = blurLayout;
		else
			return .Err;

		IBindGroupLayout[1] blurLayouts = .(mBlurBindGroupLayout);
		if (mDevice.CreatePipelineLayout(.(blurLayouts)) case .Ok(let blurPlLayout))
			mBlurPipelineLayout = blurPlLayout;
		else
			return .Err;

		// Blur params buffer
		BufferDesc blurBufDesc = .()
		{
			Label = "SSAO Blur Params",
			Size = BlurParams.Size,
			Usage = .Uniform,
			Memory = .CpuToGpu
		};
		if (mDevice.CreateBuffer(blurBufDesc) case .Ok(let blurBuf))
			mBlurParamsBuffer = blurBuf;
		else
			return .Err;

		// Blur pipeline
		RenderPipelineDesc blurPipelineDesc = .()
		{
			Label = "SSAO Blur Pipeline",
			Layout = mBlurPipelineLayout,
			Vertex = .() { Shader = .(vertModule.Module, "main"), Buffers = default },
			Fragment = .() { Shader = .(blurFragModule.Module, "main"), Targets = colorTargets },
			Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
			DepthStencil = null,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (mDevice.CreateRenderPipeline(blurPipelineDesc) case .Ok(let blurPipe))
			mBlurPipeline = blurPipe;
		else
			return .Err;

		return .Ok;
	}

	public override void DeclareOutputs(RenderGraph graph, PostProcessContext ctx)
	{
		// Raw AO (unblurred) and final blurred AO that tonemap reads
		let desc = RGTextureDesc(.R8Unorm) { Usage = .RenderTarget | .Sampled };
		let rawHandle = graph.CreateTransient("AOTextureRaw", desc);
		let blurredHandle = graph.CreateTransient("AOTexture", desc);
		ctx.SetAux("AOTextureRaw", rawHandle);
		ctx.SetAux("AOTexture", blurredHandle);
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderContext renderContext, PostProcessContext ctx)
	{
		using (Profiler.Begin("SSAO"))
		{

		let rawAoHandle = ctx.GetAux("AOTextureRaw");
		let aoHandle = ctx.GetAux("AOTexture");
		if (!rawAoHandle.IsValid || !aoHandle.IsValid) return;

		let depthHandle = ctx.SceneDepth;
		let normalsHandle = ctx.SceneNormals;
		if (!depthHandle.IsValid || !normalsHandle.IsValid) return;

		// Upload generate params
		SSAOParams @params = .()
		{
			ProjectionMatrix = view.ProjectionMatrix,
			InvProjectionMatrix = .Identity,
			TexelSizeX = 1.0f / Math.Max(view.Width, 1),
			TexelSizeY = 1.0f / Math.Max(view.Height, 1),
			Radius = Radius,
			Intensity = Intensity,
			Bias = Bias,
			NearPlane = view.NearPlane,
			FarPlane = view.FarPlane
		};
		Matrix.Invert(view.ProjectionMatrix, out @params.InvProjectionMatrix);
		TransferHelper.WriteMappedBuffer(mParamsBuffer, 0,
			Span<uint8>((uint8*)&@params, SSAOParams.Size));

		// Upload blur params
		BlurParams blurParams = .()
		{
			TexelSizeX = @params.TexelSizeX,
			TexelSizeY = @params.TexelSizeY,
			DepthThreshold = 0.005f
		};
		TransferHelper.WriteMappedBuffer(mBlurParamsBuffer, 0,
			Span<uint8>((uint8*)&blurParams, BlurParams.Size));

		// Pass 1: Generate raw AO
		graph.AddRenderPass("SSAO Generate", scope (builder) => {
			builder
				.ReadTexture(depthHandle)
				.ReadTexture(normalsHandle)
				.SetColorTarget(0, rawAoHandle, .Clear, .Store, ClearColor(1.0f, 1.0f, 1.0f, 1.0f))
				.NeverCull()
				.SetExecute(new [=] (encoder) => {
					ExecuteSSAO(encoder, view, graph, depthHandle, normalsHandle);
				});
		});

		// Pass 2: Bilateral blur raw AO → final AO
		graph.AddRenderPass("SSAO Blur", scope (builder) => {
			builder
				.ReadTexture(rawAoHandle)
				.ReadTexture(depthHandle)
				.SetColorTarget(0, aoHandle, .DontCare, .Store)
				.NeverCull()
				.SetExecute(new [=] (encoder) => {
					ExecuteBlur(encoder, view, graph, rawAoHandle, depthHandle);
				});
		});

		// Pass through color chain unchanged — tonemap reads AOTexture aux
		ctx.Output = ctx.Input;

		} // SSAO profiler scope
	}

	private void ExecuteSSAO(IRenderPassEncoder encoder, RenderView view, RenderGraph graph,
		RGHandle depthHandle, RGHandle normalsHandle)
	{
		let depthView = graph.GetDepthOnlyTextureView(depthHandle);
		let normalsView = graph.GetTextureView(normalsHandle);
		if (depthView == null || normalsView == null) return;

		let frameSlot = view.FrameIndex % MaxFrames;

		if (mBindGroups[frameSlot] != null)
			mDevice.DestroyBindGroup(ref mBindGroups[frameSlot]);

		BindGroupEntry[5] bgEntries = .(
			BindGroupEntry.Buffer(mParamsBuffer, 0, SSAOParams.Size),
			BindGroupEntry.Buffer(mKernelBuffer, 0, 256),
			BindGroupEntry.Texture(depthView),
			BindGroupEntry.Texture(normalsView),
			BindGroupEntry.Sampler(mPointSampler)
		);

		BindGroupDesc bgDesc = .() { Label = "SSAO BindGroup", Layout = mBindGroupLayout, Entries = bgEntries };
		if (mDevice.CreateBindGroup(bgDesc) case .Ok(let bg))
			mBindGroups[frameSlot] = bg;

		if (mBindGroups[frameSlot] == null) return;

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0, 1);
		encoder.SetScissor(0, 0, view.Width, view.Height);
		encoder.SetPipeline(mPipeline);
		encoder.SetBindGroup(0, mBindGroups[frameSlot], default);
		encoder.Draw(3, 1, 0, 0);
	}

	private void ExecuteBlur(IRenderPassEncoder encoder, RenderView view, RenderGraph graph,
		RGHandle rawAoHandle, RGHandle depthHandle)
	{
		let rawAoView = graph.GetTextureView(rawAoHandle);
		let depthView = graph.GetDepthOnlyTextureView(depthHandle);
		if (rawAoView == null || depthView == null) return;

		let frameSlot = view.FrameIndex % MaxFrames;

		if (mBlurBindGroups[frameSlot] != null)
			mDevice.DestroyBindGroup(ref mBlurBindGroups[frameSlot]);

		BindGroupEntry[4] bgEntries = .(
			BindGroupEntry.Buffer(mBlurParamsBuffer, 0, BlurParams.Size),
			BindGroupEntry.Texture(rawAoView),
			BindGroupEntry.Texture(depthView),
			BindGroupEntry.Sampler(mPointSampler)
		);

		BindGroupDesc bgDesc = .() { Label = "SSAO Blur BindGroup", Layout = mBlurBindGroupLayout, Entries = bgEntries };
		if (mDevice.CreateBindGroup(bgDesc) case .Ok(let bg))
			mBlurBindGroups[frameSlot] = bg;

		if (mBlurBindGroups[frameSlot] == null) return;

		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0, 1);
		encoder.SetScissor(0, 0, view.Width, view.Height);
		encoder.SetPipeline(mBlurPipeline);
		encoder.SetBindGroup(0, mBlurBindGroups[frameSlot], default);
		encoder.Draw(3, 1, 0, 0);
	}

	/// Generates 16 Poisson-distributed hemisphere samples.
	/// Samples are in tangent space: XY random direction, Z always positive (hemisphere).
	/// Progressive scaling concentrates samples near the origin for better close-range AO.
	private void GenerateKernel()
	{
		// Simple deterministic sequence (no System.Random needed)
		float[16] hashX = .(0.32f, 0.78f, 0.15f, 0.91f, 0.47f, 0.63f, 0.28f, 0.85f,
							0.53f, 0.19f, 0.71f, 0.42f, 0.96f, 0.08f, 0.59f, 0.37f);
		float[16] hashY = .(0.67f, 0.23f, 0.89f, 0.44f, 0.12f, 0.76f, 0.55f, 0.31f,
							0.82f, 0.48f, 0.05f, 0.93f, 0.61f, 0.16f, 0.74f, 0.39f);
		float[16] hashZ = .(0.51f, 0.84f, 0.37f, 0.69f, 0.22f, 0.95f, 0.13f, 0.58f,
							0.41f, 0.73f, 0.26f, 0.87f, 0.64f, 0.09f, 0.46f, 0.81f);

		for (int i = 0; i < 16; i++)
		{
			// Random direction in hemisphere (Z > 0)
			float x = hashX[i] * 2.0f - 1.0f;
			float y = hashY[i] * 2.0f - 1.0f;
			float z = hashZ[i]; // [0, 1] — hemisphere

			var sample = Vector3(x, y, z);
			sample = Vector3.Normalize(sample);

			// Progressive scale: samples near origin are more important for close-range AO
			float scale = (float)i / 16.0f;
			scale = 0.1f + scale * scale * 0.9f; // lerp(0.1, 1.0, scale²)
			sample = sample * scale;

			mKernelSamples[i] = .(sample.X, sample.Y, sample.Z, 0);
		}
	}

	public override void OnShutdown()
	{
		if (mDevice == null) return;

		for (int i = 0; i < MaxFrames; i++)
		{
			if (mBindGroups[i] != null) mDevice.DestroyBindGroup(ref mBindGroups[i]);
			if (mBlurBindGroups[i] != null) mDevice.DestroyBindGroup(ref mBlurBindGroups[i]);
		}

		if (mPipeline != null) mDevice.DestroyRenderPipeline(ref mPipeline);
		if (mPipelineLayout != null) mDevice.DestroyPipelineLayout(ref mPipelineLayout);
		if (mBindGroupLayout != null) mDevice.DestroyBindGroupLayout(ref mBindGroupLayout);
		if (mBlurPipeline != null) mDevice.DestroyRenderPipeline(ref mBlurPipeline);
		if (mBlurPipelineLayout != null) mDevice.DestroyPipelineLayout(ref mBlurPipelineLayout);
		if (mBlurBindGroupLayout != null) mDevice.DestroyBindGroupLayout(ref mBlurBindGroupLayout);
		if (mBlurParamsBuffer != null) mDevice.DestroyBuffer(ref mBlurParamsBuffer);
		if (mPointSampler != null) mDevice.DestroySampler(ref mPointSampler);
		if (mParamsBuffer != null) mDevice.DestroyBuffer(ref mParamsBuffer);
		if (mKernelBuffer != null) mDevice.DestroyBuffer(ref mKernelBuffer);
	}

	[CRepr]
	private struct SSAOParams
	{
		public Matrix ProjectionMatrix;
		public Matrix InvProjectionMatrix;
		public float TexelSizeX;
		public float TexelSizeY;
		public float Radius;
		public float Intensity;
		public float Bias;
		public float NearPlane;
		public float FarPlane;
		public float _Pad;
		public const uint64 Size = sizeof(Self);
	}

	[CRepr]
	private struct BlurParams
	{
		public float TexelSizeX;
		public float TexelSizeY;
		public float DepthThreshold;
		public float _Pad;
		public const uint64 Size = 16;
	}
}
