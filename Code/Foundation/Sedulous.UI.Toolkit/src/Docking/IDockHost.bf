namespace Sedulous.UI.Toolkit;

using Sedulous.UI;

/// Interface for the docking system host that manages floating panels.
/// Implemented by DockManager.
public interface IDockHost
{
	void FloatPanel(DockablePanel panel, float x, float y);
	void DestroyDockableWindow(DockableWindow fw);
	UIContext Context { get; }
}
