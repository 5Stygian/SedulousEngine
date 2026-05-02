namespace Sedulous.UI2;

using System;

/// Identifies a position in a hierarchical or flat model.
/// Row is the item index within its parent. Parent is the parent index
/// (Invalid for top-level items in a flat model).
public struct ModelIndex : IHashable, IEquatable<ModelIndex>
{
	/// Row index within the parent.
	public int32 Row;

	/// Parent index (Invalid for root-level items).
	public ModelIndex* Parent;

	/// Internal pointer for the model to associate data (e.g., tree node pointer).
	public void* InternalPtr;

	public static readonly ModelIndex Invalid = .() { Row = -1 };

	public bool IsValid => Row >= 0;

	public this() { Row = -1; Parent = null; InternalPtr = null; }
	public this(int32 row) { Row = row; Parent = null; InternalPtr = null; }
	public this(int32 row, void* internalPtr) { Row = row; Parent = null; InternalPtr = internalPtr; }

	public int GetHashCode() => Row;
	public bool Equals(ModelIndex other) => Row == other.Row && InternalPtr == other.InternalPtr;
	public static bool operator ==(ModelIndex a, ModelIndex b) => a.Row == b.Row && a.InternalPtr == b.InternalPtr;
	public static bool operator !=(ModelIndex a, ModelIndex b) => !(a == b);
}
