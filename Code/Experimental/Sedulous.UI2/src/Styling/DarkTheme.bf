namespace Sedulous.UI2;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;

/// Factory for creating the default dark theme as a StyleSheet.
/// Returns a new StyleSheet with refcount 1. Caller must manage the ref.
public static class DarkTheme
{
	public static StyleSheet Create()
	{
		let p = ThemePalette.Dark;
		return BuildTheme(p);
	}

	public static StyleSheet Create(ThemePalette palette)
	{
		return BuildTheme(palette);
	}

	private static StyleSheet BuildTheme(ThemePalette p)
	{
		let sheet = new StyleSheet();

		// === Global defaults (View base type) ===
		sheet.ForType(typeof(View))
			.Set(.TextColor, p.Text)
			.Set(.FontSize, 16.0f);

		// === Button ===
		let btnBg = Palette.CreateStateColors(p.SurfaceBright);
		sheet.OwnDrawable(btnBg);
		sheet.ForType(typeof(View), "button")
			.Set(.Background, btnBg)
			.Set(.TextColor, Color(240, 240, 245, 255))
			.Set(.Padding, Thickness(12, 8))
			.Set(.CornerRadius, 4.0f);

		// === Panel ===
		let panelBg = new RoundedRectDrawable(p.Surface, 6, p.Border, 1);
		sheet.OwnDrawable(panelBg);
		sheet.ForType(typeof(View), "panel")
			.Set(.Background, panelBg);

		// === Label ===
		sheet.ForType(typeof(View), "label")
			.Set(.TextColor, p.Text);

		sheet.ForType(typeof(View), "label-dim")
			.Set(.TextColor, p.TextDim);

		// === EditText ===
		let editBg = new RoundedRectDrawable(.(30, 32, 42, 255), 4, p.Border, 1);
		sheet.OwnDrawable(editBg);
		sheet.ForType(typeof(View), "edittext")
			.Set(.Background, editBg)
			.Set(.TextColor, p.Text)
			.Set(.PlaceholderColor, p.TextDim)
			.Set(.FontSize, 14.0f)
			.Set(.Padding, Thickness(6, 4))
			.Set(.CursorColor, p.PrimaryAccent)
			.Set(.SelectionColor, Color(60, 120, 200, 80));

		// === CheckBox ===
		sheet.ForType(typeof(View), "checkbox")
			.Set(.BoxColor, Color(30, 32, 42, 255))
			.Set(.BorderColor, Color(100, 105, 120, 255))
			.Set(.CheckColor, p.PrimaryAccent)
			.Set(.BoxSize, 18.0f)
			.Set(.Spacing, 6.0f);

		// === RadioButton ===
		sheet.ForType(typeof(View), "radiobutton")
			.Set(.BoxColor, Color(30, 32, 42, 255))
			.Set(.BorderColor, Color(100, 105, 120, 255))
			.Set(.CheckColor, p.PrimaryAccent);

		// === Slider ===
		sheet.ForType(typeof(View), "slider")
			.Set(.TrackColor, Color(50, 52, 62, 255))
			.Set(.FillColor, p.PrimaryAccent)
			.Set(.ThumbColor, Color(220, 220, 230, 255))
			.Set(.ThumbSize, 16.0f)
			.Set(.TrackHeight, 4.0f);

		// === ProgressBar ===
		sheet.ForType(typeof(View), "progressbar")
			.Set(.TrackColor, Color(50, 52, 62, 255))
			.Set(.FillColor, p.PrimaryAccent);

		// === ToggleSwitch ===
		sheet.ForType(typeof(View), "toggleswitch")
			.Set(.TrackColor, p.Surface)
			.Set(.TrackOnColor, p.PrimaryAccent)
			.Set(.KnobColor, Color(230, 230, 235, 255))
			.Set(.BorderColor, p.Border);

		// === ComboBox ===
		let comboBg = new RoundedRectDrawable(.(40, 42, 52, 255), 4, p.Border, 1);
		sheet.OwnDrawable(comboBg);
		sheet.ForType(typeof(View), "combobox")
			.Set(.Background, comboBg)
			.Set(.ArrowColor, Color(180, 185, 200, 255));

		// === ScrollBar ===
		sheet.ForType(typeof(View), "scrollbar")
			.Set(.TrackColor, Color(40, 42, 50, 150))
			.Set(.ThumbColor, Color(100, 110, 130, 200));

		// === Separator ===
		sheet.ForType(typeof(View), "separator")
			.Set(.BorderColor, p.Border);

		// === Expander ===
		let expanderBg = new ColorDrawable(.(50, 55, 68, 255));
		sheet.OwnDrawable(expanderBg);
		sheet.ForType(typeof(View), "expander")
			.Set(.Background, expanderBg);

		// Apply registered extensions.
		ThemeRegistry.ApplyExtensions(sheet, p);

		return sheet;
	}
}
