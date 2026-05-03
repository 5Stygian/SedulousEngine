namespace Sedulous.UI2;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;

/// Factory for creating a light theme as a StyleSheet.
/// Returns a new StyleSheet with refcount 1. Caller must manage the ref.
public static class LightTheme
{
	public static StyleSheet Create()
	{
		return BuildTheme(.Light);
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
		let btnBg = Palette.CreateStateColors(.(220, 222, 230, 255));
		let btnChecked = Palette.CreateStateColors(p.PrimaryAccent);
		sheet.OwnDrawable(btnBg);
		sheet.OwnDrawable(btnChecked);
		sheet.ForType(typeof(View), "button")
			.Set(.Background, btnBg)
			.Set(.CheckedBackground, btnChecked)
			.Set(.TextColor, Color(30, 30, 40, 255))
			.Set(.Padding, Thickness(12, 8))
			.Set(.CornerRadius, 0.0f);

		// === Panel ===
		let panelBg = new RoundedRectDrawable(p.Surface, 0, p.Border, 1);
		sheet.OwnDrawable(panelBg);
		sheet.ForType(typeof(View), "panel")
			.Set(.Background, panelBg);

		// === Label ===
		sheet.ForType(typeof(View), "label")
			.Set(.TextColor, p.Text);

		sheet.ForType(typeof(View), "label-dim")
			.Set(.TextColor, p.TextDim);

		// === EditText ===
		let editBg = new RoundedRectDrawable(p.Surface, 0, p.Border, 1);
		sheet.OwnDrawable(editBg);
		sheet.ForType(typeof(View), "edittext")
			.Set(.Background, editBg)
			.Set(.TextColor, p.Text)
			.Set(.PlaceholderColor, p.TextDim)
			.Set(.FontSize, 14.0f)
			.Set(.Padding, Thickness(6, 4))
			.Set(.CursorColor, p.PrimaryAccent)
			.Set(.SelectionColor, Color(60, 120, 200, 60));

		// === CheckBox ===
		{
			let cbUnchecked = new RoundedRectDrawable(p.Surface, 0, p.Border, 1);
			let cbChecked = new RoundedRectDrawable(p.PrimaryAccent, 0, p.Border, 1);
			sheet.OwnDrawable(cbUnchecked);
			sheet.OwnDrawable(cbChecked);
			sheet.ForType(typeof(View), "checkbox")
				.Set(.BoxDrawable, cbUnchecked)
				.Set(.CheckedBackground, cbChecked)
				.Set(.BoxSize, 18.0f)
				.Set(.Spacing, 6.0f);
		}

		// === RadioButton ===
		{
			let rbUnchecked = new RoundedRectDrawable(p.Surface, 0, p.Border, 1);
			let rbChecked = new RoundedRectDrawable(p.PrimaryAccent, 0, p.Border, 1);
			sheet.OwnDrawable(rbUnchecked);
			sheet.OwnDrawable(rbChecked);
			sheet.ForType(typeof(View), "radiobutton")
				.Set(.BoxDrawable, rbUnchecked)
				.Set(.CheckedBackground, rbChecked);
		}

		// === Slider ===
		sheet.ForType(typeof(View), "slider")
			.Set(.TrackDrawable, sheet.OwnColor(.(210, 215, 225, 255)))
			.Set(.FillDrawable, sheet.OwnColor(p.PrimaryAccent))
			.Set(.ThumbDrawable, sheet.OwnColor(p.PrimaryAccent))
			.Set(.ThumbSize, 16.0f)
			.Set(.TrackHeight, 4.0f);

		// === ProgressBar ===
		sheet.ForType(typeof(View), "progressbar")
			.Set(.TrackDrawable, sheet.OwnColor(.(210, 215, 225, 255)))
			.Set(.FillDrawable, sheet.OwnColor(p.PrimaryAccent));

		// === ToggleSwitch ===
		{
			let swOff = new RoundedRectDrawable(.(200, 205, 215, 255), 0, p.Border, 1);
			let swOn = new RoundedRectDrawable(p.PrimaryAccent, 0, p.Border, 1);
			sheet.OwnDrawable(swOff);
			sheet.OwnDrawable(swOn);
			sheet.ForType(typeof(View), "toggleswitch")
				.Set(.TrackDrawable, swOff)
				.Set(.TrackOnDrawable, swOn)
				.Set(.KnobDrawable, sheet.OwnColor(p.Surface));
		}

		// === ComboBox ===
		let comboBg = new RoundedRectDrawable(p.Surface, 0, p.Border, 1);
		sheet.OwnDrawable(comboBg);
		sheet.ForType(typeof(View), "combobox")
			.Set(.Background, comboBg)
			.Set(.ArrowColor, Color(80, 85, 100, 255));

		// === ScrollBar ===
		sheet.ForType(typeof(View), "scrollbar")
			.Set(.TrackDrawable, sheet.OwnColor(.(230, 232, 240, 150)))
			.Set(.ThumbDrawable, sheet.OwnColor(.(160, 165, 180, 200)));

		// === Separator ===
		sheet.ForType(typeof(View), "separator")
			.Set(.BorderColor, p.Border);

		// === Expander ===
		sheet.ForType(typeof(View), "expander")
			.Set(.HeaderDrawable, sheet.OwnColor(.(235, 238, 245, 255)))
			.Set(.HeaderHoverDrawable, sheet.OwnColor(Palette.Darken(.(235, 238, 245, 255), 0.05f)))
			.Set(.ArrowColor, Color(80, 85, 100, 255));

		// === TabView ===
		sheet.ForType(typeof(View), "tabview")
			.Set(.StripDrawable, sheet.OwnColor(Palette.Darken(p.Surface, 0.05f)))
			.Set(.ContentDrawable, sheet.OwnColor(p.Surface))
			.Set(.ActiveTabDrawable, sheet.OwnColor(p.Surface))
			.Set(.HoverTabDrawable, sheet.OwnColor(Palette.Darken(p.Surface, 0.03f)))
			.Set(.BorderColor, p.Border)
			.Set(.AccentColor, p.PrimaryAccent)
			.Set(.ActiveTabTextColor, p.Text)
			.Set(.InactiveTabTextColor, p.TextDim)
			.Set(.HoverTabTextColor, Palette.Darken(p.TextDim, 0.2f))
			.Set(.CloseButtonColor, p.TextDim)
			.Set(.CloseButtonHoverColor, p.Text);

		// === Icons ===
		RegisterIcons(sheet);

		// Apply registered extensions.
		ThemeRegistry.ApplyExtensions(sheet, p);

		return sheet;
	}

	private static void RegisterIcons(StyleSheet sheet)
	{
		void Reg(StyleProperty prop, StringView svg, StringView styleId = default)
		{
			let d = SVGDrawable.FromString(svg);
			if (d != null)
			{
				sheet.OwnDrawable(d);
				if (styleId.IsEmpty)
					sheet.ForType(typeof(View)).Set(prop, d);
				else
					sheet.ForType(typeof(View), styleId).Set(prop, d);
			}
		}

		Reg(.CheckmarkIcon, ThemeIcons.Checkmark, "checkbox");
		Reg(.RadioMarkIcon, ThemeIcons.RadioMarkSquare, "radiobutton");
		Reg(.CloseIcon, ThemeIcons.Close, "tabview");
		Reg(.ChevronExpandedIcon, ThemeIcons.ChevronDown, "expander");
		Reg(.ChevronCollapsedIcon, ThemeIcons.ChevronRight, "expander");
		Reg(.ArrowDownIcon, ThemeIcons.ArrowDown, "combobox");
	}
}
