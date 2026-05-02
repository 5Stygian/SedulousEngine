namespace Sedulous.UI2;

/// Identifies a style property that can be set in a StyleRule.
/// Each property has a known value type (Color, float, Thickness, Drawable, bool).
public enum StyleProperty
{
	// === Drawable properties ===
	Background,
	Foreground,           // not a drawable — see StyleValue, but some controls use drawable
	CheckedBackground,
	TrackDrawable,
	ThumbDrawable,

	// === Color properties ===
	TextColor,            // inheritable
	PlaceholderColor,
	BorderColor,
	CursorColor,
	SelectionColor,
	TrackColor,
	FillColor,
	ThumbColor,
	KnobColor,
	CheckColor,
	BoxColor,
	ArrowColor,
	TrackOnColor,

	// === Float properties ===
	FontSize,             // inheritable
	CornerRadius,
	BorderWidth,
	Spacing,
	ThumbSize,
	TrackHeight,
	BoxSize,
	Opacity,

	// === Thickness properties ===
	Padding,
	Margin,

	// === Bool properties ===
	WordWrap,

	/// Number of known properties (for array sizing).
	COUNT
}
