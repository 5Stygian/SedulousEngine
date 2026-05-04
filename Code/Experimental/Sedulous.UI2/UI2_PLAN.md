# Sedulous.UI2 — Framework Plan

Clean-slate UI framework for the Sedulous engine. Keeps the View/ViewGroup model
and LayoutParams pattern from Sedulous.UI but replaces MeasureSpec with BoxConstraints,
adds CSS Flex-inspired containers, and fixes the defaults and friction points
discovered building real applications.

Sedulous.UI remains stable with ~700 unit tests. UI2 is experimental — if it works
out, projects migrate. If not, lessons inform improvements to UI.

---

## Phase 0 — Infrastructure (COMPLETE)

All core infrastructure is in place (~90 source files, ~240 tests passing).

**Core:** View, ViewGroup, RootView, UIContext, ViewId, ViewTransform, Thickness,
Visibility, CursorType, MutationQueue, IClipboard, Property<T>, Orientation

**Layout:** Unit (Dp/Pt/Px), BoxConstraints, SizeSpec, LayoutParams, Gravity,
GravityHelper

**Drawing:** UIDrawContext, ControlState, Drawable base + 12 concrete drawables
(Color, Image, RoundedRect, NineSlice, Gradient, Atlas variants, SVG,
StateList, Layer, Inset, Shape)

**Styling:** StyleSheet (RefCounted, shareable between contexts), StyleRule,
StyleSelector (Type + StyleClass + ControlState matching with specificity cascade),
StyleProperty, StyleValue (discriminated union), Palette (seed color generation).
Drawable ownership is explicit via StyleSheet.OwnDrawable().

**Input:** InputManager, FocusManager, ShortcutManager, Shortcut,
IAcceleratorHandler, KeyCode, KeyModifiers, MouseButton, 4 event args types

**Overlay:** PopupLayer (with position factory callback), PopupEntry,
PopupPositioner, ModalBackdrop, IPopupOwner, TooltipManager, TooltipView,
TooltipPlacement, ITooltipProvider

**DragDrop:** DragDropManager, DragData, DragAdorner, DragDropEffects,
IDragSource, IDropTarget

**Editing:** TextEditingBehavior, ITextEditHost, UndoStack, InputFilter

**Animation:** Animation, AnimationManager, Easing (full curve library),
FloatAnimation, ColorAnimation, Vector2Animation, Storyboard, ViewAnimator

**Debug:** UIDebugDrawSettings, UIDebugOverlay

**Data:** IModel, ModelIndex

**Shell Bridge:** UIInputHelper, InputMapping, ShellClipboardAdapter

**Runtime:** UI2Subsystem (with input routing, clipboard bridge, cursor sync)

**Sandbox:** UI2Sandbox app (Application-based, not EngineApplication)

---

## Phase 1 — Containers (COMPLETE)

All 6 layout containers implemented with ~75 tests passing.

**Containers:**
- FlexLayout — Direction, JustifyContent (6 modes), AlignItems (5 modes),
  Spacing, Grow/Shrink/AlignSelf per child
- GridLayout — TrackSize (Auto/Fixed/Flex), Columns, Rows, AutoFlow,
  ColumnSpacing/RowSpacing, ColumnSpan/RowSpan
- DockLayout — Dock (Left/Top/Right/Bottom/Fill), LastChildFill (default false)
- FrameLayout — Gravity positioning (loosened constraints for children)
- AbsoluteLayout — Explicit X/Y positioning
- FlowLayout — Wrapping horizontal/vertical flow with HSpacing/VSpacing

**Supporting types:** Orientation, GravityHelper, Justify, Align, Dock, TrackSize

**Sandbox:** Visual demo showing all layouts (FlexLayout main, DockLayout left,
GridLayout center, FlowLayout right, header/footer)

---

## Phase 2 — Themes (COMPLETE)

Three themes implemented as StyleSheet factories. All visual regions are drawable-based
(ColorDrawable for flat, RoundedRectDrawable for rounded). Icons use SVGDrawable.

**Theme system:**
- ThemePalette — Seed color struct with Dark and Light presets (Primary, PrimaryAccent,
  Background, Surface, SurfaceBright, Border, Text, TextDim, Error, Success, Warning)
- DarkTheme — Flat/squared theme with StateList drawables, no corner radii
- LightTheme — Flat/squared with light palette, visible borders on all controls
- RoundedDarkTheme — Consistent R=6 corner radii, pill-shaped toggle switch,
  per-corner radius masking on TabView for placement-aware rounding
- ThemeRegistry — Central extension registry applied to all theme factories
- IThemeExtension — Interface for injecting custom rules into themes
- ThemeIcons — SVG icon constants (checkmark, radio mark square/round, close,
  chevrons, arrows). Themes register appropriate variants.
- RoundedRectDrawable — Upgraded to per-corner CornerRadii (from VG)

**Drawable-based styling:** Controls resolve all visual regions as Drawables
(Background, CheckedBackground, BoxDrawable, TrackDrawable, etc.). VG drawing
is only used as fallback when no theme is set. Icons (checkmark, radio mark,
close button, chevrons, arrows) are SVGDrawable, allowing resolution-independent
rendering without subpixel artifacts.

**Sandbox:** F5 cycles Dark → Light → RoundedDark themes.

---

## Phase 3 — Basic Controls (COMPLETE)

All controls implemented with drawable-based theming, SVG icons, and full sandbox demo.

- [x] Button — background drawable (StateListDrawable), ControlState, OnClick
- [x] RepeatButton — fires OnClick repeatedly while held
- [x] Label — text, HAlign/VAlign, word wrap
- [x] Panel — background drawable, padding container
- [x] Separator — orientation, color, thickness
- [x] Spacer — empty spacing view
- [x] CheckBox — toggle with CheckedBackground + CheckmarkIcon (SVG), OnCheckedChanged
- [x] RadioButton + RadioGroup — exclusive selection, RadioMarkIcon (square/round per theme)
- [x] ToggleButton — checked/unchecked backgrounds from theme
- [x] ToggleSwitch — track/knob drawables, border baked into drawable
- [x] Slider — TrackDrawable/FillDrawable/ThumbDrawable, value range, drag
- [x] ProgressBar — TrackDrawable/FillDrawable, value 0-1
- [x] ImageView — image display with ScaleType (None/FitCenter/FillBounds/CenterCrop), tint
- [x] ColorView — solid color swatch
- [x] Expander — collapsible header with ChevronExpandedIcon/ChevronCollapsedIcon (SVG)
- [x] ScrollView — VisualChild pattern for scrollbars, Overlay/Reserved modes,
      horizontal+vertical scrolling, shift+wheel for horizontal, mouse drag on scrollbars
- [x] ScrollBar — standalone scrollbar, thumb drag, page click
- [x] TabView — tab headers with placement (Top/Bottom/Left/Right), closable tabs with
      CloseIcon (SVG), placement-aware corner radius masking, accent indicator bar
- [x] **Tests:** Control tests, ScrollView tests, TabView tests
- [x] **UI2Sandbox:** Full controls demo with all controls, ScrollView modes,
      tab placement grid, F5 theme cycling (Dark/Light/RoundedDark)

---

## Phase 4 — Text Input (COMPLETE)

Text editing controls built on TextEditingBehavior/ITextEditHost infrastructure.

- [x] EditText — single/multi-line, placeholder, read-only, max length, input filter,
      prefix/suffix slots (StringView or View), cursor blink, selection highlight,
      auto-scroll, mouse wheel scroll for multiline
- [x] PasswordBox — masked display (customizable mask char), copy/cut disabled
- [x] NumericField — optional spin buttons (ShowSpinButtons), drawable-based button
      backgrounds with per-corner rounding, prefix/suffix, value clamping, decimal
      places formatting, mouse wheel increment, repeat timer, arrow key navigation
- [x] EditableLabel — dual-mode label/editor, slow-click (0.4-1.5s) and double-click
      entry, ValidateRename delegate, commit/cancel with text restore
- [x] **Tests:** 31 tests — EditText (text get/set, max length, input filter, read-only,
      cursor movement, select all, delete, PasswordBox masking/copy disabled),
      NumericField (clamping, step, events, formatting, filter), EditableLabel
      (mode transitions, commit/cancel, validation, unchanged rejection)
- [x] **UI2Sandbox:** Text Input tab with all variants including vector3-style editor
      demo with colored prefix views

**Design decisions implemented:**
- Prefix/suffix: `SetPrefix(StringView)` / `SetPrefix(View)`, same for suffix.
  View prefixes are laid out before drawing so Width/Height are set.
- NumericField: `ShowSpinButtons = true` default. Spin button backgrounds are
  SpinUpDrawable/SpinDownDrawable (StateListDrawable) from theme. Cursor switches
  to Arrow over spin buttons.
- EditableLabel: composition building block, styling via context not subclassing.

**Bug fixes during implementation:**
- FlexLayout grow children forced to infinite cross-axis height via Tight constraints
- ScrollView Auto horizontal policy gave infinite width to children
- Multiline cursor navigation skipped empty lines (no-glyph lines)
- GlyphToCharIndex didn't account for line boundaries (trailing vs leading hit)
- EnsureCursorVisible fought mouse wheel scrolling (now only on cursor movement)

---

## Phase 5 — Data Controls (COMPLETE)

Adapter-based data controls replacing the original IModel/ModelIndex plan.
Uses IListAdapter/ITreeAdapter pattern from current UI (Android-style adapters).

- [x] IListAdapter + IListAdapterObserver + ListAdapterBase — flat list data source
      with view creation, binding, variable height, view types, observer notifications
- [x] ITreeAdapter + ITreeAdapterObserver — tree data source with node IDs
- [x] FlattenedTreeAdapter — wraps ITreeAdapter as IListAdapter, expansion state,
      GetExpandedNodes/SetExpandedNodes for state capture
- [x] ViewRecycler — view pooling by type with diagnostic counters
- [x] SelectionModel — None/Single/Multiple modes, Select/Deselect/Toggle/SelectRange,
      ShiftIndices for insert/remove, OnSelectionChanged event
- [x] ListView — virtualized list with fixed/variable height (binary search), ViewRecycler,
      SelectionModel, momentum scrolling, keyboard nav (Up/Down/Home/End/PageUp/PageDown
      with Shift for range), Ctrl+click toggle, long-press detection, scrollbar VisualChild,
      ScreenToLocal for correct click coordinates
- [x] TreeView — wraps ListView + FlattenedTreeAdapter, themed chevron icons
      (ChevronExpandedIcon/ChevronCollapsedIcon), VG fallback, IndentWidth/ArrowSize,
      Left/Right arrow keys expand/collapse, OnItemClick/OnItemToggled events
- [x] GridView — new virtualized flowing grid, fixed CellWidth/CellHeight/CellSpacing,
      columns computed from available width, row-based virtualization, keyboard nav
      (arrows/Home/End/PageUp/PageDown), selection highlight
- [x] HierarchicalState — capture/restore TreeView state (expanded nodes, selection, scroll)
      via FlattenedTreeAdapter.GetExpandedNodes/SetExpandedNodes public API
- [x] **Tests:** 39 tests — DataTests (ViewRecycler, SelectionModel, FlattenedTreeAdapter),
      ListViewTests, TreeViewTests, GridViewTests
- [x] **UI2Sandbox:** Data Controls tab with 1000-item ListView, hierarchical TreeView
      with TreeItemView depth-based indentation, 200-cell colored GridView

**Design decision:** IModel/ModelIndex replaced with adapter pattern. Adapters own view
creation and binding (proven Android-style pattern). IModel was deleted.

**Regression fixes applied concurrently:**
- IsEffectivelyEnabled guards added to CheckBox, RadioButton, Slider, ToggleSwitch, Expander
- Cursor = .Hand added to all interactive controls
- ImageView Image/ScaleType converted to properties with invalidation
- Button.GetControlState checks Command.CanExecute()
- Expander.SetHeaderText/Expand/Collapse added
- TabView.AddTab returns int32, MinTabWidth, ClipsContent added
- ToggleSwitch.OnToggled renamed to OnCheckedChanged for consistency
- ScrollView: drag-to-scroll, ScrollToView, ScrollToLeft/Right, ContentWidth/Height
- View.QueueDestroy and View.ScrollIntoView added

---

## Phase 6 — Overlays + Dialogs (COMPLETE)

Overlay controls built on PopupLayer/TooltipManager infrastructure.

- [x] MenuItem — text-only data class with label, action, enabled, separator, submenu
- [x] ContextMenu — popup menu with full keyboard navigation (Up/Down/Enter/Right/Left/Escape),
      submenu support, themed MenuItemHoverDrawable, submenu arrow via ChevronCollapsedIcon,
      explicit submenu lifecycle cleanup via stored PopupLayer reference
- [x] Dialog — modal popup with title, content area (Grow=1), button row (JustifyContent=.End),
      DialogResult enum, Escape closes with Cancel, static Alert/Confirm factories,
      VisualChild pattern for internal FlexLayout
- [x] ComboBox — dedicated ComboBoxDropdown panel (not ContextMenu) matching parent width,
      selected item highlight, hover drawable from theme, AddItem(StringView) API,
      keyboard navigation (Up/Down/Space/Enter/Escape)
- [x] TooltipView — themed via StyleId "tooltip", drawable-based background, tooltip content
      now creates Label for plain text (was missing)
- [x] SVGDrawable — TintColor property for theme-aware icon colors (light theme uses dark tint)
- [x] EditText — right-click context menu (Cut/Copy/Paste/Select All), suppressible via
      ShowContextMenuOnRightClick property
- [x] **Tests:** 23 tests — ContextMenuTests (7), DialogTests (7), ComboBoxTests (9)
- [x] **UI2Sandbox:** Overlays tab (ComboBox, Dialog buttons, right-click ContextMenu with
      nested submenus, tooltips with bottom/top/right/interactive/rich content),
      Drag & Drop tab (chip reorder + drop target), Animations tab (fade/bounce/slide +
      static transforms with hit-test verification)

**Improvements over current UI:**
- ContextMenu has full keyboard navigation (current UI has none)
- ComboBox uses dedicated dropdown panel instead of ContextMenu (matches width, highlights selected)
- Submenu lifecycle: explicit PopupLayer reference cleanup (no OnDetachedFromContext needed)
- SVGDrawable tint: one icon set for all themes, color controlled by theme

**Bug fixes during implementation:**
- AttachView/DetachView now recurse through VisualChildren (not just regular children),
  fixing focus cleanup crash when Dialog buttons were deleted without unregistering
- Separator missing StyleId causing hardcoded dark color in light theme
- TooltipManager was clearing content instead of creating Label for plain text tooltips

**Design decisions:**
- MenuItem: text-only (no icon/shortcut slots yet). MenuBar in Phase 7 will use
  purpose-built MenuBarItem with dropdown containing regular MenuItems.
- ComboBox: simple AddItem(StringView) API. IModel support deferred to Phase 5.
- MenuItemHoverDrawable: dedicated drawable property for item hover (flat for square
  themes, rounded for rounded theme)

---

## Phase 7 — Toolkit

Advanced controls for editor and application chrome.

- [ ] DockManager + DockablePanel + DockSplit + DockTabGroup
- [ ] DockZoneIndicator — visual feedback during dock drag
- [ ] MenuBar — horizontal menu with dropdown items
- [ ] Toolbar + ToolbarButton + ToolbarSeparator
- [ ] StatusBar — bottom status line with sections
- [ ] SplitView — draggable divider, persistent SplitRatio with PersistenceId
- [ ] BreadcrumbBar — path segments as clickable buttons, OnSegmentClicked event
- [ ] PropertyGrid + editors (Bool, Int, Float, String, Enum, Range, Color, Vector3)
- [ ] DraggableTreeView — TreeView with drag reorder
- [ ] ColorPicker — interactive color selection
- [ ] **Tests:** PropertyGrid editor creation per type
- [ ] **Tests:** DockManager panel add/remove/reparent
- [ ] **Tests:** BreadcrumbBar segment clicks
- [ ] **UI2Sandbox:** Toolkit demo page (docking, property grid, menus, toolbar)

---

## Phase 8 — Runtime Integration + XML Loading

Bridge UI2 with the engine runtime and add declarative layout loading.

- [ ] UI2Subsystem enhancements — theme setup, clipboard bridge, cursor sync
- [ ] Shell integration — input dispatch from shell events to InputManager
- [ ] XML layout loader — element names → View types (factory registry), attributes → properties + LayoutParams
- [ ] XML id resolution — FindById<T> after load
- [ ] XML styleClass attribute → View.StyleId for stylesheet matching
- [ ] **Tests:** XML loader creates correct view hierarchy from XML string
- [ ] **Tests:** XML attributes map to correct properties and LayoutParams
- [ ] **UI2Sandbox:** XML layout demo page

---

## Phase 9 — Migration

Port existing applications from Sedulous.UI to UI2.

- [ ] Port UISandbox demos to UI2 (verify feature parity)
- [ ] Port editor to UI2
- [ ] Port tower defense game UI to UI2
- [ ] Remove Sedulous.UI dependency from migrated projects
- [ ] Performance comparison: measure/layout time UI vs UI2

---

## Layout Specifications

### How BoxConstraints flow through each container

**FlexLayout:**
1. Compute available main-axis space from parent BoxConstraints (minus spacing, padding)
2. Measure inflexible children (Grow == 0) with loose constraints on both axes, main-axis capped at remaining space
3. Distribute remaining main-axis space among flexible children by Grow ratios
4. If overflow, shrink flexible children by Shrink ratios
5. Apply JustifyContent for leftover space distribution on main axis
6. Apply AlignItems for cross-axis positioning (per-child AlignSelf overrides)

**GridLayout:**
1. Initialize Fixed tracks upfront (independent of children)
2. Measure Auto tracks (content-driven, max of children in that track)
3. Distribute remaining space among Flex tracks by weight
4. Place children in cells, constrained by cell size (spanning adds spacing)

**DockLayout:**
1. Process children in order. Each docked child gets:
   - Top/Bottom: full remaining width, measured height
   - Left/Right: measured width, full remaining height
   - Fill: all remaining space
2. Each docked child shrinks the remaining area for subsequent children.

**FrameLayout:**
1. Each child measured with loosened constraints (min=0, max=parent minus padding/margin)
2. Positioned via Gravity within the frame bounds

**AbsoluteLayout:**
1. Each child measured with loose constraints
2. Positioned at explicit X/Y from LayoutParams

**FlowLayout:**
1. Children measured with AtMost(remainingLineSpace) width
2. Placed left-to-right (or top-to-bottom)
3. Wraps to next line when space exhausted

---

## Control Specifications

### Button

**Properties:**
- `View Content` — arbitrary content (default: Label when constructed with text)
- `Drawable Background` — inline override, null = resolve from StyleSheet
- `ICommand Command` — optional command binding

**Events:** `Event<delegate void(Button)> OnClick`

**State:** ControlState drives StyleSheet state matching. Overrides GetControlState to add Pressed.

### Label

**Properties:**
- `String Text`
- `HAlign HAlign` — Left / Center / Right
- `VAlign VAlign` — Top / Middle / Bottom
- `bool WordWrap`, `bool Ellipsis`, `int32 MaxLines`

### EditText

**Properties:**
- `String Text`, `String Placeholder`
- `bool IsReadOnly`, `int32 MaxLength`, `bool Multiline`
- `InputFilter Filter`

**Events:** `OnTextChanged`, `OnSubmit`

**Internal:** TextEditingBehavior

### Content-bearing Controls

Button, ToggleButton, and Expander have a `View Content` property. Set it to
a Label for text (default), ImageView for icon, or Flex with icon+text.

Controls with fixed visual structure (CheckBox, RadioButton, ToggleSwitch,
Slider, ProgressBar) use String properties, not Content.

---

## Design Decisions

### Input handler chaining is per-control, not on View

Views that need multiple prioritized input handlers (e.g., viewport with
camera orbit + gizmo + selection) implement handler lists themselves in their
OnMouseDown/OnMouseUp overrides. This avoids adding a handler list to every
View when only 2-3 controls need it.

### IModel is minimal

IModel provides GetItemCount, GetDisplayText, HasChildren, GetChildCount,
GetChildIndex, GetParent, and OnDataChanged. No role-based dispatch — controls
query the data they need through the interface directly. Typed model
implementations (ListModel<T>, TreeModel) provide the concrete data.

### Property<T> uses operator constraint

`where bool : operator T == T` allows a single Property<T> class for both
value types and reference types. No separate RefProperty needed.

### Unit resolves at layout time

Unit (Dp/Pt/Px) stores intent. Resolution to pixels happens during measure/layout
when RootView.DpiScale is available. Thickness and other resolved values use raw
floats — they are already in pixel space after resolution.

### PopupLayer lives on RootView

Popups are scoped per-window (per RootView), not per UIContext. This naturally
handles multi-window scenarios. Position factory callback (AUI-inspired) provides
smart positioning with fallback candidates.

### ShortcutManager dispatch order

1. Escape → cancel drag
2. Tab → focus navigation
3. Focused view → bubble up parent chain (if Handled, stop)
4. ShortcutManager → scoped shortcuts first, then global
5. Alt+key → IAcceleratorHandler top-down tree search

### StyleSheet is RefCounted

StyleSheet extends RefCounted so it can be shared between multiple UIContexts
(e.g., screen-space UI and world-space UI sharing the same theme). UIContext
AddRefs on set, ReleaseRefs on change or destruction.

### Drawable ownership in StyleSheet is explicit

Drawables stored in StyleSheet rules are not automatically owned. Callers must
register drawables with `sheet.OwnDrawable(drawable)` to transfer ownership.
This avoids ambiguity about who deletes shared drawables and allows drawables
to be referenced by multiple rules without double-delete.

### Style cascade resolution (no caching)

StyleSheet resolution walks rules in specificity order each time a property is
queried. No per-view caching. With typical rule counts (<100) this is fast enough.
Caching can be added later if profiling shows it's needed. Avoids dirty tracking
complexity for inheritable properties that would need to propagate through the tree.

### Inheritable style properties

TextColor and FontSize inherit from parent if not found on the view itself.
Background, Padding, Margin, and all other properties do not inherit.
Inheritance walks the parent chain recursively through StyleSheet.Resolve().
