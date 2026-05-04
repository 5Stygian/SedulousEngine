namespace UISandbox;

using Sedulous.LegacyUI;
using Sedulous.LegacyUI.Runtime;
using Sedulous.LegacyUI.Toolkit;
using Sedulous.Images;

/// Shared resources for demo pages.
class DemoContext
{
	public LegacyUISubsystem UI;
	public OwnedImageData Checkerboard;
	public OwnedImageData ButtonNormal;
	public OwnedImageData ButtonPressed;
	public Label ClickLabel; // shared feedback label across pages
	public IDockableWindowHost DockableWindowHost;
}
