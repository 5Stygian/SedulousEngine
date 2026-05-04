namespace UISandbox;

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

		let app = scope UISandboxApp();
		return app.Run(.()
		{
			Title = "UI Sandbox",
			Width = 1280,
			Height = 720,
			EnableShaderCache = true
		});
	}
}
