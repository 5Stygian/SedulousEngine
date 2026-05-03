namespace Sedulous.UI2;

using System;
using Sedulous.Core.Mathematics;

/// Main-axis content distribution.
public enum Justify { Start, End, Center, SpaceBetween, SpaceAround, SpaceEvenly }

/// Cross-axis alignment.
public enum Align { Start, End, Center, Stretch, Baseline }

/// CSS Flexbox-inspired container. Replaces LinearLayout with grow/shrink
/// distribution, justify content, and cross-axis alignment.
public class FlexLayout : ViewGroup
{
	/// Main axis direction.
	public Orientation Direction = .Horizontal;

	/// How to distribute extra space on the main axis.
	public Justify JustifyContent = .Start;

	/// Default cross-axis alignment for children.
	public Align AlignItems = .Stretch;

	/// Spacing between children on the main axis.
	public float Spacing;

	public class LayoutParams : Sedulous.UI2.LayoutParams
	{
		/// How much extra main-axis space this child absorbs (0 = fixed).
		public float Grow = 0;

		/// How much this child shrinks when space is insufficient (0 = no shrink).
		public float Shrink = 0;

		/// Cross-axis override for this child (null = use parent's AlignItems).
		public Align? AlignSelf;

		/// Cross-axis gravity (for positioning within allocated cross-axis space).
		public Gravity Gravity = .None;
	}

	protected override Sedulous.UI2.LayoutParams CreateDefaultLayoutParams()
		=> new FlexLayout.LayoutParams();

	protected override void OnMeasure(BoxConstraints constraints)
	{
		let inner = constraints.Deflate(Padding);

		if (Direction == .Horizontal)
			MeasureHorizontal(inner, constraints);
		else
			MeasureVertical(inner, constraints);
	}

	private void MeasureHorizontal(BoxConstraints inner, BoxConstraints outer)
	{
		float totalFixed = 0;
		float maxCross = 0;
		float totalGrow = 0;
		int visibleCount = 0;

		// Pass 1: measure inflexible children
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone) continue;
			visibleCount++;

			let flp = child.LayoutParams as FlexLayout.LayoutParams;
			let grow = (flp != null) ? flp.Grow : 0;

			if (grow > 0)
			{
				totalGrow += grow;
				continue; // measured in pass 2
			}

			child.Measure(MakeChildConstraints(inner, child));
			let margin = child.LayoutParams?.Margin ?? Thickness();
			totalFixed += child.MeasuredSize.X + margin.TotalHorizontal;
			maxCross = Math.Max(maxCross, child.MeasuredSize.Y + margin.TotalVertical);
		}

		// Add spacing
		if (visibleCount > 1)
			totalFixed += Spacing * (visibleCount - 1);

		// Pass 2: distribute remaining space to grow children
		if (totalGrow > 0)
		{
			let remaining = Math.Max(0, inner.MaxWidth - totalFixed);

			for (int i = 0; i < ChildCount; i++)
			{
				let child = GetChildAt(i);
				if (child.Visibility == .Gone) continue;

				let flp = child.LayoutParams as FlexLayout.LayoutParams;
				let grow = (flp != null) ? flp.Grow : 0;
				if (grow <= 0) continue;

				let margin = child.LayoutParams?.Margin ?? Thickness();
				let childMain = remaining * grow / totalGrow;

				// Main axis tight, cross axis loose (child determines own height).
				let crossMax = Math.Max(0, inner.MaxHeight - margin.TotalVertical);
				let childConstraints = BoxConstraints(
					childMain - margin.TotalHorizontal, Math.Max(0, childMain - margin.TotalHorizontal),
					0, crossMax);
				child.Measure(childConstraints);
				totalFixed += childMain;
				maxCross = Math.Max(maxCross, child.MeasuredSize.Y + margin.TotalVertical);
			}
		}

		MeasuredSize = .(
			outer.ConstrainWidth(totalFixed + Padding.TotalHorizontal),
			outer.ConstrainHeight(maxCross + Padding.TotalVertical));
	}

	private void MeasureVertical(BoxConstraints inner, BoxConstraints outer)
	{
		float totalFixed = 0;
		float maxCross = 0;
		float totalGrow = 0;
		int visibleCount = 0;

		// Pass 1: measure inflexible children
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone) continue;
			visibleCount++;

			let flp = child.LayoutParams as FlexLayout.LayoutParams;
			let grow = (flp != null) ? flp.Grow : 0;

			if (grow > 0)
			{
				totalGrow += grow;
				continue;
			}

			child.Measure(MakeChildConstraints(inner, child));
			let margin = child.LayoutParams?.Margin ?? Thickness();
			totalFixed += child.MeasuredSize.Y + margin.TotalVertical;
			maxCross = Math.Max(maxCross, child.MeasuredSize.X + margin.TotalHorizontal);
		}

		if (visibleCount > 1)
			totalFixed += Spacing * (visibleCount - 1);

		// Pass 2: distribute remaining space to grow children
		if (totalGrow > 0)
		{
			let remaining = Math.Max(0, inner.MaxHeight - totalFixed);

			for (int i = 0; i < ChildCount; i++)
			{
				let child = GetChildAt(i);
				if (child.Visibility == .Gone) continue;

				let flp = child.LayoutParams as FlexLayout.LayoutParams;
				let grow = (flp != null) ? flp.Grow : 0;
				if (grow <= 0) continue;

				let margin = child.LayoutParams?.Margin ?? Thickness();
				let childMain = remaining * grow / totalGrow;

				// Main axis tight, cross axis loose (child determines own width).
				let crossMax = Math.Max(0, inner.MaxWidth - margin.TotalHorizontal);
				let childConstraints = BoxConstraints(
					0, crossMax,
					childMain - margin.TotalVertical, Math.Max(0, childMain - margin.TotalVertical));
				child.Measure(childConstraints);
				totalFixed += childMain;
				maxCross = Math.Max(maxCross, child.MeasuredSize.X + margin.TotalHorizontal);
			}
		}

		MeasuredSize = .(
			outer.ConstrainWidth(maxCross + Padding.TotalHorizontal),
			outer.ConstrainHeight(totalFixed + Padding.TotalVertical));
	}

	protected override void OnLayout(float left, float top, float width, float height)
	{
		if (Direction == .Horizontal)
			LayoutHorizontal(width, height);
		else
			LayoutVertical(width, height);
	}

	private void LayoutHorizontal(float width, float height)
	{
		let contentW = width - Padding.TotalHorizontal;
		let contentH = height - Padding.TotalVertical;

		// Compute total main-axis size of children.
		float totalMain = 0;
		int visibleCount = 0;
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone) continue;
			visibleCount++;
			let margin = child.LayoutParams?.Margin ?? Thickness();
			totalMain += child.MeasuredSize.X + margin.TotalHorizontal;
		}
		if (visibleCount > 1)
			totalMain += Spacing * (visibleCount - 1);

		// Compute justify offsets.
		float startOffset = 0;
		float gap = Spacing;
		ComputeJustify(JustifyContent, contentW, totalMain, visibleCount, ref startOffset, ref gap);

		var xPos = Padding.Left + startOffset;
		bool first = true;

		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone) continue;

			if (!first) xPos += gap;
			first = false;

			let margin = child.LayoutParams?.Margin ?? Thickness();
			let flp = child.LayoutParams as FlexLayout.LayoutParams;
			let align = (flp?.AlignSelf != null) ? flp.AlignSelf.Value : AlignItems;

			let childW = child.MeasuredSize.X;
			let childH = child.MeasuredSize.Y;
			let availCross = contentH - margin.TotalVertical;

			var yPos = Padding.Top + margin.Top;
			var finalH = childH;

			switch (align)
			{
			case .Start:    yPos = Padding.Top + margin.Top;
			case .End:      yPos = Padding.Top + contentH - margin.Bottom - childH;
			case .Center:   yPos = Padding.Top + margin.Top + (availCross - childH) * 0.5f;
			case .Stretch:  yPos = Padding.Top + margin.Top; finalH = availCross;
			case .Baseline:
				let bl = child.GetBaseline();
				if (bl >= 0) yPos = Padding.Top + margin.Top; // simplified baseline
				else yPos = Padding.Top + margin.Top;
			}

			child.Layout(xPos + margin.Left, yPos, childW, Math.Max(0, finalH));
			xPos += childW + margin.TotalHorizontal;
		}
	}

	private void LayoutVertical(float width, float height)
	{
		let contentW = width - Padding.TotalHorizontal;
		let contentH = height - Padding.TotalVertical;

		float totalMain = 0;
		int visibleCount = 0;
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone) continue;
			visibleCount++;
			let margin = child.LayoutParams?.Margin ?? Thickness();
			totalMain += child.MeasuredSize.Y + margin.TotalVertical;
		}
		if (visibleCount > 1)
			totalMain += Spacing * (visibleCount - 1);

		float startOffset = 0;
		float gap = Spacing;
		ComputeJustify(JustifyContent, contentH, totalMain, visibleCount, ref startOffset, ref gap);

		var yPos = Padding.Top + startOffset;
		bool first = true;

		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			if (child.Visibility == .Gone) continue;

			if (!first) yPos += gap;
			first = false;

			let margin = child.LayoutParams?.Margin ?? Thickness();
			let flp = child.LayoutParams as FlexLayout.LayoutParams;
			let align = (flp?.AlignSelf != null) ? flp.AlignSelf.Value : AlignItems;

			let childW = child.MeasuredSize.X;
			let childH = child.MeasuredSize.Y;
			let availCross = contentW - margin.TotalHorizontal;

			var xPos = Padding.Left + margin.Left;
			var finalW = childW;

			switch (align)
			{
			case .Start:    xPos = Padding.Left + margin.Left;
			case .End:      xPos = Padding.Left + contentW - margin.Right - childW;
			case .Center:   xPos = Padding.Left + margin.Left + (availCross - childW) * 0.5f;
			case .Stretch:  xPos = Padding.Left + margin.Left; finalW = availCross;
			case .Baseline: xPos = Padding.Left + margin.Left;
			}

			child.Layout(xPos, yPos + margin.Top, Math.Max(0, finalW), childH);
			yPos += childH + margin.TotalVertical;
		}
	}

	/// Compute start offset and gap for JustifyContent distribution.
	private static void ComputeJustify(Justify justify, float containerSize, float totalChildSize,
		int childCount, ref float startOffset, ref float gap)
	{
		let freeSpace = Math.Max(0, containerSize - totalChildSize);

		switch (justify)
		{
		case .Start:
			// default — no changes
		case .End:
			startOffset = freeSpace;
		case .Center:
			startOffset = freeSpace * 0.5f;
		case .SpaceBetween:
			if (childCount > 1)
				gap += freeSpace / (childCount - 1);
		case .SpaceAround:
			if (childCount > 0)
			{
				let around = freeSpace / childCount;
				startOffset = around * 0.5f;
				gap += around;
			}
		case .SpaceEvenly:
			if (childCount > 0)
			{
				let even = freeSpace / (childCount + 1);
				startOffset = even;
				gap += even;
			}
		}
	}
}
