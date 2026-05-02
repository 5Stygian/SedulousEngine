namespace UI2Sandbox;

using System;
using Sedulous.Runtime.Client;
using Sedulous.Images.STB;
using Sedulous.Images.SDL;

class Program
{
	public static int Main(String[] args)
	{
		STBImageLoader.Initialize();
		SDLImageLoader.Initialize();

		let app = scope UI2SandboxApp();
		return app.Run(.()
		{
			Title = "UI2 Sandbox",
			Width = 1280,
			Height = 720,
			EnableShaderCache = true
		});
	}
}
