namespace Sedulous.UI2;

using System;
using Sedulous.Core.Mathematics;

/// Content-bearing button with click event and optional ICommand binding.
/// Construct with text for a simple text button, or set Content manually
/// for icon, icon+text, or custom content.
public class Button : View
{
	private View mContent ~ delete _;
	private bool mIsPressed;

	/// Per-instance background override (owned by this view).
	public Drawable Background ~ delete _;

	/// Optional command binding. Executed on click if CanExecute() is true.
	public ICommand Command;

	/// Click event.
	public Event<delegate void(Button)> OnClick ~ _.Dispose();

	/// The content view (owned by this button).
	public View Content
	{
		get => mContent;
		set
		{
			delete mContent;
			mContent = value;
			Invalidate();
		}
	}

	/// Whether the button is currently pressed (visual state).
	public bool IsPressed => mIsPressed;

	/// Text button constructor - creates a Label as content.
	public this(StringView text)
	{
		IsFocusable = true;
		IsTabStop = true;
		StyleId = new String("button");
		mContent = new Label(text);
	}

	/// Empty button - set Content manually.
	public this()
	{
		IsFocusable = true;
		IsTabStop = true;
		StyleId = new String("button");
	}

	public override ControlState GetControlState()
	{
		if (!IsEffectivelyEnabled) return .Disabled;
		if (Command != null && !Command.CanExecute()) return .Disabled;
		if (mIsPressed) return .Pressed;
		if (IsFocused) return .Focused;
		if (IsHovered) return .Hover;
		return .Normal;
	}

	protected override void OnMeasure(BoxConstraints constraints)
	{
		let pad = ResolveStyleThickness(.Padding, .(12, 8));
		let inner = constraints.Deflate(pad).Loosen();

		float contentW = 0, contentH = 0;
		if (mContent != null)
		{
			// Pass font context down to content for measurement
			if (mContent.Context == null && Context != null)
				Context.AttachView(mContent);
			mContent.Measure(inner);
			contentW = mContent.MeasuredSize.X;
			contentH = mContent.MeasuredSize.Y;
		}

		MeasuredSize = .(
			constraints.ConstrainWidth(contentW + pad.TotalHorizontal),
			constraints.ConstrainHeight(contentH + pad.TotalVertical));
	}

	protected override void OnLayout(float left, float top, float width, float height)
	{
		if (mContent == null) return;

		let pad = ResolveStyleThickness(.Padding, .(12, 8));
		let contentW = width - pad.TotalHorizontal;
		let contentH = height - pad.TotalVertical;

		// Center content within padding
		let cw = mContent.MeasuredSize.X;
		let ch = mContent.MeasuredSize.Y;
		let cx = pad.Left + (contentW - cw) * 0.5f;
		let cy = pad.Top + (contentH - ch) * 0.5f;
		mContent.Layout(cx, cy, cw, ch);
	}

	public override void OnDraw(UIDrawContext ctx)
	{
		let bounds = RectangleF(0, 0, Width, Height);
		let state = GetControlState();
		let radius = ResolveStyleFloat(.CornerRadius, 4);

		// Background: per-instance -> theme drawable -> fallback
		if (Background != null)
		{
			Background.Draw(ctx, bounds, state);
		}
		else
		{
			let themeBg = ResolveStyleDrawable(.Background);
			if (themeBg != null)
			{
				themeBg.Draw(ctx, bounds, state);
			}
			else
				DrawDefaultBackground(ctx, bounds, state, radius);
		}

		// Draw content
		if (mContent != null)
		{
			ctx.VG.PushState();
			ctx.VG.Translate(mContent.Bounds.X, mContent.Bounds.Y);
			mContent.OnDraw(ctx);
			ctx.VG.PopState();
		}
	}

	private void DrawDefaultBackground(UIDrawContext ctx, RectangleF bounds, ControlState state, float radius)
	{
		Color bg = .(55, 58, 70, 255);
		switch (state)
		{
		case .Hover:    bg = Palette.ComputeHover(bg);
		case .Pressed:  bg = Palette.ComputePressed(bg);
		case .Disabled: bg = Palette.ComputeDisabled(bg);
		case .Focused:  bg = Palette.ComputeFocused(bg);
		default:
		}

		if (radius > 0)
			ctx.VG.FillRoundedRect(bounds, radius, bg);
		else
			ctx.VG.FillRect(bounds, bg);
	}

	/// Fire the click event and execute command if bound.
	public void FireClick()
	{
		if (!IsEffectivelyEnabled) return;
		if (Command != null && !Command.CanExecute()) return;

		OnClick(this);
		Command?.Execute();
	}

	public override void OnMouseDown(MouseEventArgs e)
	{
		if (e.Button == .Left)
		{
			mIsPressed = true;
			Invalidate();
			e.Handled = true;
		}
	}

	public override void OnMouseUp(MouseEventArgs e)
	{
		if (e.Button == .Left && mIsPressed)
		{
			mIsPressed = false;
			Invalidate();

			// Fire click if mouse is still over this button
			if (IsHovered)
				FireClick();

			e.Handled = true;
		}
	}

	public override void OnKeyDown(KeyEventArgs e)
	{
		if (e.Key == .Return || e.Key == .Space)
		{
			FireClick();
			e.Handled = true;
		}
	}
}
