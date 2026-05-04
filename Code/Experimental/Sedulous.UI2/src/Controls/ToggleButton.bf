namespace Sedulous.UI2;

using System;
using Sedulous.Core.Mathematics;

/// Stateful button that toggles between checked and unchecked.
/// Content-bearing - set Content for custom content, or construct with text.
public class ToggleButton : View
{
	private View mContent ~ delete _;
	private bool mIsChecked;
	private bool mIsPressed;

	/// Per-instance background for unchecked state (owned).
	public Drawable Background ~ delete _;

	/// Per-instance background for checked state (owned).
	public Drawable CheckedBackground ~ delete _;

	/// Whether the toggle is checked.
	public bool IsChecked
	{
		get => mIsChecked;
		set
		{
			if (mIsChecked == value) return;
			mIsChecked = value;
			Invalidate();
			OnCheckedChanged(this, mIsChecked);
		}
	}

	public View Content
	{
		get => mContent;
		set { delete mContent; mContent = value; Invalidate(); }
	}

	public Event<delegate void(ToggleButton, bool)> OnCheckedChanged ~ _.Dispose();

	public this(StringView text)
	{
		IsFocusable = true;
		IsTabStop = true;
		StyleId = new String("button");
		mContent = new Label(text);
	}

	public this() { IsFocusable = true; IsTabStop = true; StyleId = new String("button"); }

	public override ControlState GetControlState()
	{
		if (!IsEffectivelyEnabled) return .Disabled;
		if (mIsPressed) return .Pressed;
		if (IsFocused) return .Focused;
		if (IsHovered) return .Hover;
		return .Normal;
	}

	protected override void OnMeasure(BoxConstraints constraints)
	{
		let pad = ResolveStyleThickness(.Padding, .(12, 8));
		let inner = constraints.Deflate(pad).Loosen();

		float cw = 0, ch = 0;
		if (mContent != null)
		{
			if (mContent.Context == null && Context != null)
				Context.AttachView(mContent);
			mContent.Measure(inner);
			cw = mContent.MeasuredSize.X;
			ch = mContent.MeasuredSize.Y;
		}

		MeasuredSize = .(constraints.ConstrainWidth(cw + pad.TotalHorizontal),
			constraints.ConstrainHeight(ch + pad.TotalVertical));
	}

	protected override void OnLayout(float left, float top, float width, float height)
	{
		if (mContent == null) return;
		let pad = ResolveStyleThickness(.Padding, .(12, 8));
		let contentW = width - pad.TotalHorizontal;
		let contentH = height - pad.TotalVertical;
		let cx = pad.Left + (contentW - mContent.MeasuredSize.X) * 0.5f;
		let cy = pad.Top + (contentH - mContent.MeasuredSize.Y) * 0.5f;
		mContent.Layout(cx, cy, mContent.MeasuredSize.X, mContent.MeasuredSize.Y);
	}

	public override void OnDraw(UIDrawContext ctx)
	{
		let bounds = RectangleF(0, 0, Width, Height);
		let state = GetControlState();
		let radius = ResolveStyleFloat(.CornerRadius, 4);

		// Background based on checked state
		let bg = mIsChecked ? (CheckedBackground ?? Background) : Background;
		if (bg != null)
		{
			bg.Draw(ctx, bounds, state);
		}
		else if (mIsChecked)
		{
			// Checked: try CheckedBackground from theme, fall back to accent color
			let checkedBg = ResolveStyleDrawable(.CheckedBackground);
			if (checkedBg != null)
				checkedBg.Draw(ctx, bounds, state);
			else
			{
				var color = ResolveStyleColor(.AccentColor, .(80, 150, 240, 255));
				if (state == .Hover) color = Palette.ComputeHover(color);
				else if (state == .Pressed) color = Palette.ComputePressed(color);
				else if (state == .Disabled) color = Palette.ComputeDisabled(color);
				ctx.VG.FillRoundedRect(bounds, radius, color);
			}
		}
		else
		{
			// Unchecked: normal background from theme
			let themeBg = ResolveStyleDrawable(.Background);
			if (themeBg != null)
				themeBg.Draw(ctx, bounds, state);
			else
			{
				Color color = .(55, 58, 70, 255);
				if (state == .Hover) color = Palette.ComputeHover(color);
				else if (state == .Pressed) color = Palette.ComputePressed(color);
				else if (state == .Disabled) color = Palette.ComputeDisabled(color);
				ctx.VG.FillRoundedRect(bounds, radius, color);
			}
		}

		if (mContent != null)
		{
			ctx.VG.PushState();
			ctx.VG.Translate(mContent.Bounds.X, mContent.Bounds.Y);
			mContent.OnDraw(ctx);
			ctx.VG.PopState();
		}
	}

	public override void OnMouseDown(MouseEventArgs e)
	{
		if (e.Button == .Left) { mIsPressed = true; Invalidate(); e.Handled = true; }
	}

	public override void OnMouseUp(MouseEventArgs e)
	{
		if (e.Button == .Left && mIsPressed)
		{
			mIsPressed = false;
			if (IsHovered) IsChecked = !mIsChecked;
			Invalidate();
			e.Handled = true;
		}
	}

	public override void OnKeyDown(KeyEventArgs e)
	{
		if (e.Key == .Space || e.Key == .Return)
		{
			IsChecked = !mIsChecked;
			e.Handled = true;
		}
	}
}
