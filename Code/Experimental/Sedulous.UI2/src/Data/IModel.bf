namespace Sedulous.UI2;

using System;

/// Unified data model interface for lists and trees.
/// Controls (ListView, TreeView, ComboBox, GridView) bind to IModel
/// to display and interact with data. Supports flat and hierarchical data.
///
/// For flat lists, parent parameters are ignored and HasChildren returns false.
/// For trees, parent identifies the container node.
public interface IModel
{
	/// Number of items at the root level, or under a parent for tree models.
	int32 GetItemCount(ModelIndex parent = .());

	/// Get display text for the item at index.
	void GetDisplayText(ModelIndex index, String outText);

	/// Whether the item at index has children (for tree models).
	/// Flat models always return false.
	bool HasChildren(ModelIndex index);

	/// Number of children under the given parent (for tree models).
	int32 GetChildCount(ModelIndex parent);

	/// Get the child index at the given row under parent.
	ModelIndex GetChildIndex(int32 row, ModelIndex parent);

	/// Get the parent of the given index. Returns Invalid for root items.
	ModelIndex GetParent(ModelIndex index);

	/// Notification that the model data has changed.
	/// Controls should re-query and refresh.
	Event<delegate void()>* OnDataChanged { get; }
}
