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

## Phase 4 — Text Input

Build text editing controls on top of the TextEditingBehavior infrastructure.

- [ ] EditText — single/multi-line, placeholder, read-only, max length, input filter
- [ ] PasswordBox — masked display
- [ ] NumericField — number input with increment/decrement (wraps EditText)
- [ ] EditableLabel — label that becomes EditText on click (slow-click rename)
- [ ] **Tests:** EditText input filter, max length, submit event
- [ ] **Tests:** NumericField value clamping, step increment
- [ ] **Tests:** TextEditingBehavior cursor movement, selection, undo/redo, clipboard
- [ ] **UI2Sandbox:** Text editing demo page

---

## Phase 5 — Data Controls

Virtualized lists/trees and data model implementations.

- [ ] ListModel<T> — wraps List<T> as flat IModel
- [ ] TreeModel — hierarchical IModel implementation
- [ ] SortingProxyModel — wraps IModel with sorting
- [ ] ViewRecycler (port)
- [ ] ListView — virtualized, uses IModel (flat), fixed/variable height, selection, momentum
- [ ] FlattenedTreeAdapter (port, adapted for IModel)
- [ ] TreeView — virtualized, uses IModel (hierarchical), expand/collapse, indent
- [ ] ComboBox — dropdown selection, backed by IModel
- [ ] SelectionModel — single/multi selection (port)
- [ ] GridView — virtualized flowing grid with IModel, fixed cell size
- [ ] ListView slow-click rename — delay threshold, OnSlowClickRename event
- [ ] HierarchicalState — capture/restore expand/collapse, selection, scroll for tree widgets
- [ ] TreeView.CaptureState() / ApplyState() using HierarchicalState
- [ ] **Tests:** ListModel, TreeModel, SortingProxyModel
- [ ] **Tests:** ViewRecycler pool/acquire/recycle counts
- [ ] **Tests:** ListView visible range calculation (fixed and variable height)
- [ ] **Tests:** FlattenedTreeAdapter expand/collapse, node count
- [ ] **Tests:** SelectionModel single/multi select, clear
- [ ] **Tests:** HierarchicalState capture/restore roundtrip
- [ ] **UI2Sandbox:** ListView demo (1000 items), GridView demo, TreeView demo, ComboBox demo

---

## Phase 6 — Overlays + Dialogs

Build overlay controls on top of the PopupLayer/TooltipManager infrastructure.

- [ ] Dialog — modal, auto-centered, title + content + buttons, DialogResult
- [ ] ContextMenu — popup item list, submenus, separators
- [ ] MenuItem — text + optional shortcut display text + action
- [ ] **Tests:** Dialog show/close/result lifecycle
- [ ] **Tests:** ContextMenu item click, submenu open/close
- [ ] **UI2Sandbox:** Dialog demo, context menu demo, tooltip demo

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
