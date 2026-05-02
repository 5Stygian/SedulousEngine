# Sedulous.UI2 — Framework Plan

Clean-slate UI framework for the Sedulous engine. Keeps the View/ViewGroup model
and LayoutParams pattern from Sedulous.UI but replaces MeasureSpec with BoxConstraints,
adds CSS Flex-inspired containers, and fixes the defaults and friction points
discovered building real applications.

Sedulous.UI remains stable with ~700 unit tests. UI2 is experimental — if it works
out, projects migrate. If not, lessons inform improvements to UI.

---

## Core Changes from Sedulous.UI

### 1. BoxConstraints replaces MeasureSpec

The single biggest architectural improvement. MeasureSpec's three modes
(Unspecified/AtMost/Exactly) lose information and require mode-switching logic.
BoxConstraints carries full min/max on both axes — the math is just clamping.

```beef
struct BoxConstraints
    public float MinWidth, MaxWidth;
    public float MinHeight, MaxHeight;

    // Named constructors
    static Tight(w, h)    => .(w, w, h, h)       // exact size
    static Loose(maxW, maxH) => .(0, maxW, 0, maxH) // up to max
    static Expand()       => .(0, inf, 0, inf)     // unconstrained

    Deflate(Thickness) => shrink by padding
    ConstrainWidth(w)  => Math.Clamp(w, MinWidth, MaxWidth)
    ConstrainHeight(h) => Math.Clamp(h, MinHeight, MaxHeight)
    bool IsTight       => MinWidth == MaxWidth && MinHeight == MaxHeight
```

**Mapping to old concepts:**
- `MatchParent` = parent passes tight constraint (min == max == parentSize)
- `WrapContent` = parent passes loose constraint (min = 0, max = parentSize)
- `Fixed(50)` = parent passes tight constraint (min == max == 50)

### 2. Unit type (discriminated union)

Single type for all dimensional values. Carries intent (dp vs pt vs px),
resolved at layout/draw time when DPI scale is available.

```beef
enum Unit
    case Dp(float value);   // density-independent pixels, scaled by DPI
    case Pt(float value);   // points (1/72 inch), for font sizes
    case Px(float value);   // raw pixels, no scaling

    public float Resolve(float dpiScale)
    {
        switch (this)
        {
        case .Dp(let v): return v * dpiScale;
        case .Pt(let v): return v * dpiScale * (96.0f / 72.0f);
        case .Px(let v): return v;
        }
    }
```

### 3. SizeSpec replaces sentinel values

```beef
enum SizeSpec
    case Fixed(Unit size);   // explicit size with unit
    case Match;              // fill parent
    case Wrap;               // fit content
```

Replaces `LayoutParams.MatchParent = -1` and `LayoutParams.WrapContent = -2`.
Stored on LayoutParams (Width/Height fields). Fixed case carries a Unit
so the layout engine knows how to resolve it at the correct DPI.

Usage:
```beef
child.Width = .Fixed(.Dp(200));   // 200 density-independent pixels
child.Height = .Wrap;             // fit to content
```

### 4. LayoutParams — kept, simplified

LayoutParams stays. It works and avoids polluting View with layout-specific fields.
But the base class uses SizeSpec instead of float sentinels:

```beef
class LayoutParams
    public SizeSpec Width = .Wrap;
    public SizeSpec Height = .Wrap;
    public Thickness Margin;
```

Container-specific subclasses add what they need:

```beef
class Flex.LayoutParams : LayoutParams
    public float Grow = 0;
    public float Shrink = 0;
    public Gravity Gravity = .None;  // cross-axis override

class Grid.LayoutParams : LayoutParams
    public int32 Row = -1;      // -1 = auto-flow
    public int32 Column = -1;
    public int32 RowSpan = 1;
    public int32 ColumnSpan = 1;

class DockView.LayoutParams : LayoutParams
    public Dock Dock = .Left;

class AbsoluteLayout.LayoutParams : LayoutParams
    public float X, Y;
```

### 5. Flex container (new)

Replaces LinearLayout with CSS Flexbox-inspired distribution:

```beef
class Flex : ViewGroup
    public Direction Direction = .Row;  // Row or Column
    public Justify JustifyContent = .Start;  // main-axis distribution
    public Align AlignItems = .Stretch;  // cross-axis default
    public float Spacing = 0;

    public void AddStretch(float weight = 1);  // inserts invisible flex spacer

enum Justify { Start, End, Center, SpaceBetween, SpaceAround, SpaceEvenly }
enum Align { Start, End, Center, Stretch, Baseline }
```

**Flex.LayoutParams:** Grow (absorb extra space), Shrink (yield when tight),
Gravity (per-child cross-axis override of AlignItems).

**What this eliminates:**
- Manual Spacer widgets for pushing items apart
- Per-child gravity for common alignment patterns
- Weight-only distribution (Grow + Shrink is strictly more powerful)

### 6. Grid container (improved)

```beef
class Grid : ViewGroup
    public List<TrackSize> Columns;
    public List<TrackSize> Rows;  // optional — auto-creates if omitted
    public float RowSpacing = 0;
    public float ColumnSpacing = 0;
    public bool AutoFlow = true;  // children placed left-to-right, top-to-bottom

enum TrackSize
    case Fixed(Unit size);    // explicit size with unit
    case Flex(float weight);  // proportional (like Star in current Grid)
    case Auto;                // size to content
```

Auto-flow eliminates manual Row/Column assignment for regular grids.

### 7. Better defaults

| Setting | UI (current) | UI2 |
|---------|-------------|-----|
| DockView.LastChildFill | true | false |
| Gravity default | .None | .None (but Flex.AlignItems = .Stretch covers the common case) |
| SizeSpec default | WrapContent (-2) | .Wrap |

### 8. View.OnMeasure signature change

```beef
// UI (current)
protected virtual void OnMeasure(MeasureSpec wSpec, MeasureSpec hSpec);

// UI2
protected virtual void OnMeasure(BoxConstraints constraints);
// Sets MeasuredSize = .(width, height) constrained by constraints
```

### 9. Fluent AddView (optional convenience)

AddView returns the parent for chaining:

```beef
toolbar.AddView(new Button("Save"))
       .AddView(new Button("Load"))
       .AddStretch(1)
       .AddView(new Button("Settings"));
```

### 10. Reactive Properties (Property\<T\>)

Core observable value type. Stores a value, notifies listeners on change.
Eliminates manual sync between game state and UI.

```beef
class Property<T> where T : struct
    private T mValue;
    private Event<delegate void(T)> mChanged;

    public T Value
    {
        get => mValue;
        set
        {
            if (mValue != value)
            {
                mValue = value;
                mChanged.Invoke(mValue);
            }
        }
    }

    public Event<delegate void(T)> Changed => ref mChanged;

    // Implicit conversion for reading
    public static implicit operator T(Property<T> prop) => prop.mValue;
```

**Usage — game state:**
```beef
public Property<int32> Gold = new .(250);
Gold.Value -= cost;  // auto-notifies listeners
```

**Usage — bind to label:**
```beef
gameSub.Gold.Changed.Add(new [label](value) =>
{
    label.SetText(scope String()..AppendF("Gold: {}", value));
});
```

**What this eliminates:**
- MessageBus subscriptions for simple value changes (ResourceChangedMsg unnecessary)
- Manual UpdateGold()/UpdateLives() methods
- Scattered SetText() calls across message handlers

**Two-way binding** (e.g., Property ↔ EditText) uses a guard flag to prevent
infinite loops. Helper: `Property.BindTo(widget, propertyName)`.

### 11. Draw Invalidation

Only redraw when something changes. Views track dirty state — if nothing
changed since last frame, skip the draw pass entirely.

**How it works:**
- `View.Invalidate()` — marks view as needing redraw
- Property changes (text, background, visibility) call Invalidate() automatically
- Layout changes propagate invalidation to parent
- UIContext tracks whether any view is dirty
- Renderer checks `UIContext.NeedsRedraw` before drawing
- If nothing changed, skip VG clear + draw + present

**Dirty propagation:**
- Content change → invalidate self
- Size change → invalidate self + parent (triggers re-layout)
- Visibility change → invalidate parent
- Child add/remove → invalidate parent

**Benefit:** Game UI often static between interactions. Draw invalidation means
zero GPU cost for UI when nothing changes — more budget for 3D rendering.

### 12. StyleSheet with Typed Selectors

Replaces flat theme dictionaries with a rule-based system. Rules match views
by type, style class, and state. Most specific match wins (cascade).

```beef
class StyleSheet
    public void AddRule(StyleRule rule);

struct StyleRule
    public StyleSelector Selector;
    public List<StyleProperty> Properties;

struct StyleSelector
    public Type ViewType;        // null = any type
    public StringView StyleClass;  // null = any class
    public ControlState? State;    // null = any state
    public int32 Specificity;      // computed from selector parts
```

**Building rules (type-safe, no string selectors):**
```beef
let sheet = new StyleSheet();

// All buttons
sheet.AddRule(.For<Button>()
    .Set(.Background, new ColorDrawable(.(50, 50, 50)))
    .Set(.FontSize, 14.0f)
    .Set(.Padding, Thickness(8, 4)));

// Buttons with class "primary"
sheet.AddRule(.For<Button>(".primary")
    .Set(.Background, new ColorDrawable(.(30, 100, 200))));

// Hovered buttons
sheet.AddRule(.For<Button>(state: .Hover)
    .Set(.Background, new ColorDrawable(.(70, 70, 70))));
```

**Resolution cascade (most specific wins):**
1. Inline (set directly on view instance)
2. StyleClass + State match
3. StyleClass match
4. Type + State match
5. Type match
6. Theme default

**Property inheritance:**
Some properties inherit from parent if not set on child:
- Inherits: TextColor, FontSize, FontFamily, Cursor
- Does not inherit: Background, Padding, Margin, Border

**Replaces:** Flat theme dictionaries + per-control nullable overrides with ?? fallback.

### 13. Unified IModel (replaces IListAdapter + ITreeAdapter)

Single model interface for both flat lists and hierarchical trees.
ListView uses it flat (parent = Root). TreeView uses the hierarchy.

```beef
struct ModelIndex
    public static readonly ModelIndex Root = .();
    public int32 Row;
    public int32 Column;
    public ModelIndex Parent;
    public bool IsValid;

enum ModelRole
    Display,    // primary text
    Edit,       // editable value
    Icon,       // icon drawable
    Tooltip,    // tooltip text
    SortKey,    // sortable value
    Custom(int32)

interface IModel
    /// Number of rows under this parent (Root for flat lists).
    int32 RowCount(ModelIndex parent = .Root);

    /// Number of columns (1 for lists, N for tables).
    int32 ColumnCount(ModelIndex parent = .Root);

    /// Get a model index for a specific row/column under a parent.
    ModelIndex GetIndex(int32 row, int32 column = 0, ModelIndex parent = .Root);

    /// Get data for a given index and role.
    Variant GetData(ModelIndex index, ModelRole role = .Display);

    /// Whether this index has children (for tree expansion).
    bool HasChildren(ModelIndex index);

    /// Notifies views that data changed.
    Event<delegate void()> OnDataChanged;
```

**Built-in model implementations:**
- `ListModel<T>` — wraps a List<T>, maps to single-column rows
- `TreeModel` — hierarchical nodes with children
- `SortingProxyModel` — wraps any IModel, adds sorting

**What this replaces:**
- `IListAdapter` (CreateView, BindView, GetItemViewType, ItemCount)
- `ITreeAdapter` (HasChildren, GetChildCount, GetChild, CreateView, BindView)
- Two separate interfaces → one unified model

**ViewRecycler still used** — ListView/TreeView still pool views internally.
The model just provides the data; the view creates/recycles the visual representation.

### 14. Type-safe Units

See section 2 (Unit type). The `Unit` discriminated union (`Dp`/`Pt`/`Px`)
is used throughout the framework wherever dimensional values are needed.
`SizeSpec.Fixed` takes a `Unit`. Theme values default to `Dp`.

```beef
button.Width = .Fixed(.Dp(120));   // 120dp — scales with DPI
label.FontSize = .Pt(14);          // 14pt font
border.Thickness = .Px(1);         // always 1 raw pixel
```

`Unit.Resolve(dpiScale)` is called by the layout engine during measure/layout,
where the RootView's DpiScale is available. No global state needed.

### 15. XML Layout Loading

Declarative UI structure from XML files. Carried forward from Sedulous.UI's
UIXmlLoader. Structure in XML, styling via StyleSheet, behavior in code.

```xml
<Flex direction="Row" spacing="8">
    <Label text="Gold:" styleClass="hud-label" />
    <Label id="goldValue" styleClass="hud-value" />
</Flex>
```

**Loader resolves:**
- Element names → View types (registered in a factory)
- Attributes → LayoutParams + View properties
- `id` → retrievable via FindById after load
- `styleClass` → View.StyleId for stylesheet matching

**Not planned now:** Hot-reload of XML during runtime (future improvement).

### 16. Associative User Data on Views

Any View can store arbitrary key-value data without subclassing. Useful for
tagging widgets with application-specific context (entity handles, model
references, etc.) without creating custom View subclasses.

```beef
class View
    /// Store arbitrary data by key.
    public void SetUserData(StringView key, Object data);

    /// Retrieve stored data by key. Returns null if not set.
    public Object GetUserData(StringView key);

    /// Typed retrieval.
    public T GetUserData<T>(StringView key) where T : class;
```

Internally a lazily-allocated `Dictionary<String, Object>` — zero cost when
not used (null until first SetUserData call).

### 17. HierarchicalState Persistence

Capture and restore tree widget state (expand/collapse, selection, scroll
position) as a serializable object. Essential for editor UI where tree
state must survive reloads, undo/redo, or tab switches.

```beef
class HierarchicalState
    /// Records whether a node path is expanded.
    public void SetExpanded(StringView path, bool expanded);
    public bool IsExpanded(StringView path);

    /// Records whether a node path is selected.
    public void SetSelected(StringView path, bool selected);
    public bool IsSelected(StringView path);

    /// Scroll position.
    public float ScrollOffset;

    /// Merge another state into this one (partial updates).
    public void Merge(HierarchicalState other);
```

**Used by:** TreeView, PropertyGrid — `CaptureState()` / `ApplyState()` methods.

### 18. Editor-Informed Patterns

Patterns discovered building the Sedulous editor that need first-class support
in UI2 to avoid adhoc workarounds.

#### a. Coordinate conversion on View

Built-in local-to-screen and screen-to-local conversion. Currently the editor
implements a manual helper walking the parent chain. Used for context menu
positioning, drag-drop, and tooltip placement.

```beef
class View
    /// Converts local coordinates to screen (root-relative) coordinates.
    public Vector2 LocalToScreen(Vector2 local);

    /// Converts screen coordinates to local coordinates.
    public Vector2 ScreenToLocal(Vector2 screen);
```

Context menus should auto-position using these without user code.

#### b. Breadcrumb bar (standard component)

Navigation bar showing the current path as clickable segments. The editor
builds one manually with dynamic button generation. Should be a standard
toolkit component.

```beef
class BreadcrumbBar : ViewGroup
    public void SetPath(Span<StringView> segments);
    public Event<delegate void(int32 segmentIndex)> OnSegmentClicked;
```

#### c. GridView (virtualized flowing grid)

The editor's `GridContentView` manually reimplements ListView virtualization
for a flowing tile layout (icons, thumbnails). Should be a standard view
alongside ListView.

```beef
class GridView : ViewGroup
    public IModel Model;
    public float CellWidth, CellHeight;  // fixed cell size
    public float HSpacing, VSpacing;
    // Virtualized — only creates views for visible cells
    // ViewRecycler-based pooling, same as ListView
```

#### d. Slow-click rename detection

Distinct from double-click. After selecting an item, a short delay (0.4-1.5s)
before a second single click triggers inline rename. The editor implements
this manually. Should be a standard behavior on editable list/tree items.

```beef
class ListView
    public bool SlowClickRenameEnabled = false;
    public float SlowClickMinDelay = 0.4f;
    public float SlowClickMaxDelay = 1.5f;
    public Event<delegate void(ModelIndex)> OnSlowClickRename;
```

#### e. Keyboard shortcut manager

Global and context-aware keyboard shortcuts. The editor manually checks
key combinations in OnUpdate. Should be a framework-level service on UIContext.

```beef
class ShortcutManager  // owned by UIContext
    /// Register a global shortcut.
    public void Register(KeyCode key, KeyModifiers mods, delegate void() action,
        StringView id = default);

    /// Register a shortcut active only when a specific view/subtree has focus.
    public void RegisterScoped(View scope, KeyCode key, KeyModifiers mods,
        delegate void() action, StringView id = default);

    /// Unregister by id.
    public void Unregister(StringView id);
```

#### f. Input handler chaining

Viewport uses prioritized input handlers (gizmo handler first, camera controller
second). If the first handler doesn't consume the event, it passes to the next.
Should be a standard pattern.

```beef
interface IInputHandler
    /// Returns true if the event was handled (consumed).
    bool OnMouseDown(MouseEventArgs e);
    bool OnMouseMove(MouseEventArgs e);
    bool OnMouseUp(MouseEventArgs e);
    bool OnKeyDown(KeyEventArgs e);

class View
    /// Ordered list of input handlers. First to return true consumes the event.
    public List<IInputHandler> InputHandlers;
```

#### g. Persistent split ratios

SplitView ratios are hardcoded in the editor. Should be saveable and
restorable across sessions.

```beef
class SplitView
    public float SplitRatio { get; set; }
    public StringView PersistenceId;  // key for save/restore
```

HierarchicalState could be extended to include split ratios, or a separate
`UILayoutState` captures all persistent layout data (splits, dock positions,
column widths).

### 19. Content-bearing Controls

Some controls benefit from displaying arbitrary content instead of just text.
These controls have a `View Content` property — set it to a Label for text
(the default), an ImageView for an icon, a Flex with icon+text, or any
custom view.

**Controls with Content:**
- **Button** — content rendered inside the button's background/padding/state
- **ToggleButton** — same as Button but with toggle state
- **Expander** — header content (always visible) + body content (collapsible)

```beef
class Button : View
    private View mContent;

    public View Content
    {
        get => mContent;
        set { /* remove old, attach new, invalidate */ }
    }

    /// Convenience: creates a Label as content.
    public this(StringView text) { Content = new Label(text); }

    /// Empty button — set Content manually.
    public this() { }

    // OnMeasure: padding + content.Measure(deflated constraints)
    // OnDraw: draw background/state, then content.Draw()
```

**Usage:**
```beef
// Simple text button (default)
new Button("Save")

// Icon button
new Button() { Content = new ImageView(saveIcon) }

// Icon + text
let btn = new Button();
btn.Content = new Flex(.Row) { Spacing = 4 }
    .AddView(new ImageView(icon))
    .AddView(new Label("Save"));
```

**NOT content-bearing** (fixed visual structure, text via String property):
- CheckBox — box indicator + text, drawn manually
- RadioButton — radio indicator + text, drawn manually
- ToggleSwitch — track/knob + optional text, drawn manually
- Slider, ProgressBar, etc. — no text content model

---

## What Stays the Same

Everything not listed above carries forward from Sedulous.UI:

- **View/ViewGroup** — base classes, child management, virtual dispatch
- **RootView** — per-window root, PopupLayer as last child
- **UIContext** — central hub, ViewId registry, phase tracking, sub-managers
- **LayoutParams pattern** — per-container subclasses (just uses SizeSpec now)
- **All layouts except LinearLayout** — DockView, FrameLayout, AbsoluteLayout, FlowLayout (ported with BoxConstraints)
- **All widgets** — Button, Label, EditText, CheckBox, Slider, ListView, TreeView, etc.
- **Drawable hierarchy** — all 12 types (used within StyleSheet rules)
- **Input** — InputManager, FocusManager, DragDropManager
- **Overlays** — PopupLayer, Dialog, ContextMenu, TooltipManager
- **Animation** — FloatAnimation, ColorAnimation, Easing, Storyboard
- **Virtualization** — ViewRecycler (IModel replaces IListAdapter/ITreeAdapter)
- **Text editing** — TextEditingBehavior, UndoStack
- **Toolkit** — DockManager, PropertyGrid, MenuBar, Toolbar, etc.

---

## Control Specifications

Every control with its public properties, events, and style properties.

**Styling model:** Controls resolve visual properties via the StyleSheet cascade
(section 12). Per-instance overrides are still supported — setting a property
directly on a view takes highest priority. If not set, the StyleSheet resolves
by StyleClass + State > StyleClass > Type + State > Type > default.

**Style property names** listed below (e.g., `Button.Background`) are the keys
used in StyleSheet rules. They are NOT flat theme dictionary keys — they are
resolved through the cascade.

### View (base class)

**Identity:**
- `ViewId Id` — unique, immutable, generated on construction
- `String Name` — optional debug name
- `String StyleId` — for theme style lookup

**Layout:**
- `Vector2 MeasuredSize` — output of OnMeasure
- `RectangleF Bounds` — output of OnLayout (parent-relative)

**Visibility & Interaction:**
- `Visibility Visibility` — Visible / Gone / Hidden
- `bool IsEnabled` — grays out, disables input
- `bool IsEffectivelyEnabled` — walks parent chain
- `bool IsFocusable` — can receive keyboard focus
- `bool IsTabStop` — included in tab navigation
- `int32 TabIndex` — tab order
- `bool ClipsContent` — clip children to bounds
- `bool IsHitTestVisible` — participates in hit testing
- `bool IsInteractionEnabled` — disables entire subtree input

**Visual:**
- `float Alpha` — opacity (0-1), multiplied down tree
- `Matrix RenderTransform` — 2D transform applied before draw
- `Vector2 RenderTransformOrigin` — transform pivot (0-1 normalized)
- `CursorType Cursor` — cursor when hovered

**Tooltip:**
- `String TooltipText` — simple text tooltip
- `TooltipPlacement TooltipPlacement` — Top/Bottom/Left/Right
- `bool IsTooltipInteractive` — tooltip stays when hovered

**Virtual methods:**
- `OnMeasure(BoxConstraints constraints)`
- `OnLayout(float left, float top, float width, float height)`
- `OnDraw(UIDrawContext ctx)`
- `float GetBaseline()` — returns -1 if no baseline
- `OnKeyDown/OnKeyUp(KeyEventArgs)`
- `OnTextInput(TextInputEventArgs)`
- `OnMouseDown/OnMouseUp/OnMouseMove(MouseEventArgs)`
- `OnMouseWheel(MouseWheelEventArgs)`
- `OnFocusGained/OnFocusLost()`

---

### Button

**Properties:**
- `View Content` — arbitrary content (default: Label when constructed with text)
- `Drawable Background` — inline override (highest cascade priority), null = resolve from StyleSheet
- `Color? TextColor` — inline override, null = resolve from StyleSheet (inherited by content Label)
- `float? FontSize` — inline override, null = resolve from StyleSheet (inherited by content Label)
- `Thickness? Padding` — inline override, null = resolve from StyleSheet
- `ICommand Command` — optional command binding

**Convenience:** `new Button("Save")` creates a Label as Content internally.
`new Button()` leaves Content null for manual setup (icon, icon+text, etc.).

**Events:**
- `Event<delegate void(Button)> OnClick`

**State:** ControlState (Normal/Hover/Pressed/Disabled/Focused) drives StyleSheet state matching.

**Style properties** (used in StyleSheet rules):
- `Button.Background` — Drawable (StateListDrawable recommended)
- `Button.Foreground` — Color
- `Button.FontSize` — float (in Dp)
- `Button.Padding` — Thickness (in Dp)
- `Button.CornerRadius` — float (in Dp)

---

### Label

**Properties:**
- `String Text`
- `Color? TextColor` — inline override, null = resolve from StyleSheet (inherits from parent)
- `float? FontSize` — inline override, null = resolve from StyleSheet (inherits from parent)
- `HAlign HAlign` — Left / Center / Right
- `VAlign VAlign` — Top / Middle / Bottom
- `bool WordWrap` — wrap at width
- `bool Ellipsis` — truncate with "..."
- `int32 MaxLines` — limit visible lines (0 = unlimited)

**Style properties:**
- `Label.Foreground` — Color (inheritable)
- `Label.FontSize` — float in Dp (inheritable)

---

### EditText

**Properties:**
- `String Text` — current text content
- `String Placeholder` — hint text when empty
- `Color? TextColor`, `Color? PlaceholderColor`
- `float? FontSize`
- `bool IsReadOnly`
- `int32 MaxLength` — 0 = unlimited
- `bool Multiline`
- `InputFilter Filter` — character validation

**Events:**
- `Event<delegate void(EditText)> OnTextChanged`
- `Event<delegate void(EditText)> OnSubmit` — Enter key

**Internal:** TextEditingBehavior (cursor, selection, undo/redo, clipboard)

**Style properties:**
- `EditText.Background` — Drawable
- `EditText.Foreground` — Color
- `EditText.PlaceholderColor` — Color
- `EditText.FontSize` — float
- `EditText.Padding` — Thickness
- `EditText.CursorColor` — Color
- `EditText.SelectionColor` — Color

---

### PasswordBox

Same as EditText but displays mask character (•). No copy to clipboard.

---

### CheckBox

**Properties:**
- `bool IsChecked`
- `String Text` — label next to checkbox
- `Color? TextColor`, `float? FontSize`

**Events:**
- `Event<delegate void(CheckBox)> OnCheckedChanged`

**Style properties:**
- `CheckBox.BoxSize` — float
- `CheckBox.BoxColor` — Color (unchecked)
- `CheckBox.CheckColor` — Color (checked)
- `CheckBox.Foreground` — Color (text)
- `CheckBox.FontSize` — float
- `CheckBox.Spacing` — float (between box and text)

---

### RadioButton

Same structure as CheckBox. Grouped via RadioGroup.

---

### RadioGroup

**Properties:**
- `int32 SelectedIndex`

**Events:**
- `Event<delegate void(RadioGroup, int32)> OnSelectionChanged`

---

### ToggleButton

**Properties:**
- `bool IsChecked`
- `View Content` — arbitrary content (default: Label when constructed with text)
- `Drawable CheckedBackground` — background when checked

**Events:**
- `Event<delegate void(ToggleButton)> OnCheckedChanged`

**Style properties:**
- `ToggleButton.Background` — Drawable (unchecked)
- `ToggleButton.CheckedBackground` — Drawable (checked)
- `ToggleButton.Foreground` — Color

---

### ToggleSwitch

**Properties:**
- `bool IsOn`
- `String OnText`, `String OffText` — optional labels

**Events:**
- `Event<delegate void(ToggleSwitch)> OnToggled`

**Style properties:**
- `ToggleSwitch.TrackColor` — Color (off)
- `ToggleSwitch.TrackOnColor` — Color (on)
- `ToggleSwitch.KnobColor` — Color
- `ToggleSwitch.Width` — float
- `ToggleSwitch.Height` — float

---

### Slider

**Properties:**
- `float Value`
- `float Min`, `float Max`
- `float Step` — snap increment (0 = continuous)
- `Orientation Orientation` — Horizontal / Vertical

**Events:**
- `Event<delegate void(Slider)> OnValueChanged`
- `Event<delegate void(Slider)> OnDragStarted`
- `Event<delegate void(Slider)> OnDragEnded`

**Style properties:**
- `Slider.TrackColor` — Color
- `Slider.FillColor` — Color
- `Slider.ThumbColor` — Color
- `Slider.ThumbSize` — float
- `Slider.TrackHeight` — float

---

### NumericField

**Properties:**
- `float Value`
- `float Min`, `float Max`
- `float Step`
- `int32 DecimalPlaces`

**Events:**
- `Event<delegate void(NumericField)> OnValueChanged`

---

### ProgressBar

**Properties:**
- `float Value` — 0 to 1
- `bool IsIndeterminate` — animated without specific progress

**Style properties:**
- `ProgressBar.Background` — Color/Drawable (track)
- `ProgressBar.FillColor` — Color/Drawable (fill)
- `ProgressBar.Height` — float

---

### ComboBox

**Properties:**
- `int32 SelectedIndex`
- `IModel Model` — data source (flat, single column). Also accepts `List<String>` via `ListModel<String>` convenience.

**Events:**
- `Event<delegate void(ComboBox)> OnSelectionChanged`

**Style properties:**
- `ComboBox.Background` — Drawable
- `ComboBox.Foreground` — Color
- `ComboBox.FontSize` — float
- `ComboBox.ArrowColor` — Color

---

### Panel

**Properties:**
- `Drawable Background`
- `Thickness Padding`

Simple container with background. Children laid out based on parent's layout rules.

---

### Separator

**Properties:**
- `Orientation Orientation`
- `Color? Color`
- `float Thickness` — default 1

---

### Spacer

Empty view for explicit spacing. In UI2, mostly replaced by Flex.Spacing and
JustifyContent, but kept for explicit gaps in non-Flex containers.

---

### ImageView

**Properties:**
- `IImageData Image`
- `ScaleType ScaleType` — None / FitCenter / FillBounds / CenterCrop

---

### ColorView

**Properties:**
- `Color Color`

---

### Expander

**Properties:**
- `bool IsExpanded`
- `View Header` — content shown in collapsed state (default: Label when constructed with text)
- `View Content` — expandable body content

**Events:**
- `Event<delegate void(Expander)> OnExpandedChanged`

---

### ScrollView

**Properties:**
- `ScrollBarMode HScrollBarMode` — Never / AsNeeded / Always
- `ScrollBarMode VScrollBarMode`
- `Vector2 ScrollOffset` — current scroll position
- `bool MomentumEnabled` — inertial scrolling

**Methods:**
- `ScrollTo(float x, float y)`
- `ScrollToView(View child)`
- `ScrollToTop/Bottom/Left/Right()`

**Internal:** MomentumHelper for physics-based scrolling.

---

### ListView

**Properties:**
- `IModel Model` — unified model (flat: parent = Root)
- `SelectionModel Selection`
- `float FixedItemHeight` — 0 = variable height
- `bool MomentumEnabled`

**Events:**
- `Event<delegate void(ModelIndex)> OnItemClicked`
- `Event<delegate void(ModelIndex)> OnItemRightClicked`
- `Event<delegate void(ModelIndex)> OnItemLongPress`

**Internal:** ViewRecycler for view pooling. Binary search for variable-height visible range.

---

### TreeView

**Properties:**
- `IModel Model` — unified model (hierarchical: uses HasChildren/parent)
- `SelectionModel Selection`
- `float IndentWidth` — per-level indent
- `float ArrowSize` — expand/collapse arrow

**Events:**
- `Event<delegate void(ModelIndex)> OnItemClicked`
- `Event<delegate void(ModelIndex)> OnItemToggled`

**Internal:** FlattenedTreeAdapter + ListView for virtualization. Same IModel interface as ListView.

---

### TabView

**Properties:**
- `int32 SelectedIndex`
- `TabPlacement Placement` — Top / Bottom / Left / Right
- `bool TabsClosable`

**Events:**
- `Event<delegate void(TabView, int32)> OnTabChanged`
- `Event<delegate void(TabView, int32)> OnTabCloseRequested`

**Methods:**
- `AddTab(StringView title, View content)`
- `RemoveTab(int32 index)`

---

### Dialog

**Properties:**
- `String Title`
- `float MaxWidth`, `float MaxHeight`
- `DialogResult Result`

**Events:**
- `Event<delegate void(Dialog, DialogResult)> OnClosed`

**Methods:**
- `SetContent(View content)`
- `AddButton(StringView text, DialogResult result) -> Button`
- `Show(UIContext ctx)` — auto-centered modal
- `Close(DialogResult result)`

---

### ContextMenu

**Methods:**
- `AddItem(StringView text, delegate void() action)`
- `AddSeparator()`
- `Show(UIContext ctx, float x, float y)`

---

## Layout Specifications

### How BoxConstraints flow through each container

**Flex:**
1. Compute available main-axis space from parent BoxConstraints (minus spacing, padding)
2. Measure inflexible children (Grow == 0) with loose constraints on both axes, main-axis capped at remaining space
3. Distribute remaining main-axis space among flexible children by Grow ratios
4. If overflow, shrink flexible children by Shrink ratios
5. Apply JustifyContent for leftover space distribution on main axis
6. Apply AlignItems for cross-axis positioning (per-child Gravity overrides)

**Grid:**
1. Measure Auto tracks (content-driven)
2. Distribute remaining space among Flex tracks by weight
3. Fixed tracks get exact size
4. Place children in cells, constrained by cell size

**DockView:**
1. Process children in order. Each docked child gets:
   - Top/Bottom: full remaining width, measured height
   - Left/Right: measured width, full remaining height
   - Fill: all remaining space
2. Each docked child shrinks the remaining area for subsequent children.

**FrameLayout:**
1. Each child measured with parent constraints (minus padding/margin)
2. Positioned via Gravity within the frame bounds

**AbsoluteLayout:**
1. Each child measured with loose constraints
2. Positioned at explicit X/Y from LayoutParams

**FlowLayout:**
1. Children measured with AtMost(remainingLineSpace) width
2. Placed left-to-right (or top-to-bottom)
3. Wraps to next line when space exhausted

---

## Debug Visualization

Port from Sedulous.UI and extend. UIDebugDrawSettings flags toggle overlays
drawn after the normal render pass. Zero overhead when all flags are false.

**Debug overlays (port from UI):**
- `ShowBounds` — red outline around every view
- `ShowPadding` — green fill for padding region
- `ShowMargin` — orange fill for margin region
- `ShowDrawablePadding` — blue fill for drawable-contributed padding
- `ShowHitTarget` — yellow highlight on hovered view
- `ShowFocusPath` — blue outline on focused view + ancestors
- `ShowTabOrder` — numbered focus arrows
- `ShowRecyclerStats` — Created/Recycled/Reused counters on ListViews
- `ShowZOrder` — numbered overlay showing draw order

**New in UI2:**
- `ShowConstraints` — display BoxConstraints (min/max) on each view
- `ShowFlexInfo` — show Grow/Shrink/Basis values on Flex children
- `ShowGridLines` — draw grid track boundaries and cell outlines
- `ShowLayoutTime` — per-view measure/layout time in microseconds

**Toggle keys in UI2Sandbox:**
- F2: ShowBounds
- F3: ShowPadding + ShowMargin
- F4: ShowHitTarget + ShowFocusPath
- F5: Theme cycle (Dark/Light)

---

## Implementation Phases

### Phase 0 — Infrastructure & UI2Sandbox

Get the sandbox application running with window, rendering, font loading,
and a minimal UI context. No widgets yet — just the shell that future phases
build on.

- [ ] UI2Sandbox BeefProj.toml — dependencies on Sedulous.UI2, engine libs, SDL3, VG, Fonts, Shell
- [ ] UI2Sandbox Program.bf — entry point, creates UI2SandboxApp
- [ ] UI2Sandbox UI2SandboxApp.bf — inherits EngineApplication, creates window, initializes VGRenderer, font service
- [ ] Sedulous.UI2 BeefProj.toml — core library project
- [ ] Sedulous.UI2.Tests BeefProj.toml — test project
- [ ] Minimal UIContext — ViewId registry, phase tracking (no input/focus yet)
- [ ] Minimal RootView — viewport size, DpiScale
- [ ] UI2Sandbox renders an empty RootView (VG clear + present)
- [ ] Verify: window opens, clears to theme background color, resizes correctly

### Phase 1 — Core Layout

- [ ] Unit enum (Dp/Pt/Px discriminated union with Resolve(dpiScale))
- [ ] BoxConstraints struct with Tight/Loose/Expand/Deflate/Constrain
- [ ] SizeSpec enum (Fixed(Unit)/Match/Wrap)
- [ ] LayoutParams base class with SizeSpec Width/Height, Margin
- [ ] View base class — OnMeasure(BoxConstraints), OnLayout, MeasuredSize, Bounds, Visibility, Alpha, user data (SetUserData/GetUserData), LocalToScreen/ScreenToLocal coordinate conversion
- [ ] ViewGroup — AddView/RemoveView with LayoutParams, child iteration, padding, fluent AddView return
- [ ] Gravity flags (Left/Right/CenterH/FillH, Top/Bottom/CenterV/FillV, Center, Fill)
- [ ] Flex container — Direction, JustifyContent, AlignItems, Spacing, AddStretch
- [ ] Flex.LayoutParams — Grow, Shrink, Gravity
- [ ] Grid container — TrackSize (Fixed/Flex/Auto), Columns, Rows, AutoFlow, Spacing
- [ ] Grid.LayoutParams — Row, Column, RowSpan, ColumnSpan
- [ ] DockView — ported with BoxConstraints, LastChildFill default = false
- [ ] DockView.LayoutParams — Dock enum
- [ ] FrameLayout — ported with BoxConstraints
- [ ] AbsoluteLayout — ported with BoxConstraints
- [ ] FlowLayout — ported with BoxConstraints
- [ ] **Tests:** Unit.Resolve (Dp/Pt/Px at various DPI scales)
- [ ] **Tests:** View user data (SetUserData/GetUserData, typed retrieval, null when not set)
- [ ] **Tests:** View LocalToScreen/ScreenToLocal (nested views, with padding/margin)
- [ ] **Tests:** BoxConstraints math (Tight/Loose/Deflate/Constrain), SizeSpec resolution
- [ ] **Tests:** Flex layout (row, column, grow, shrink, justify, align, spacing, wrap)
- [ ] **Tests:** Grid layout (auto/fixed/flex tracks, auto-flow, spanning)
- [ ] **Tests:** DockView (top/bottom/left/right/fill, LastChildFill false)
- [ ] **Tests:** FrameLayout (gravity positioning)
- [ ] **Tests:** FlowLayout (wrapping)
- [ ] **UI2Sandbox:** Flex row/column demo page, Grid demo page with auto-flow

### Phase 2 — Drawing + Theme + StyleSheet

- [ ] UIDrawContext wrapping VGContext (opacity, transform, clipping stacks)
- [ ] Draw invalidation — dirty tracking on View, UIContext.NeedsRedraw flag
- [ ] Drawable base class (Draw, IntrinsicSize, DrawablePadding)
- [ ] ColorDrawable, RoundedRectDrawable, GradientDrawable
- [ ] NineSliceDrawable, AtlasNineSliceDrawable, ImageDrawable, AtlasImageDrawable
- [ ] SVGDrawable, ShapeDrawable, LayerDrawable, InsetDrawable
- [ ] ControlState enum + StateListDrawable
- [ ] Palette — seed colors, Lighten/Darken/ComputeHover/Pressed/Disabled/Focused
- [ ] StyleSheet — typed selectors, rule matching by Type + StyleClass + State
- [ ] StyleRule, StyleSelector, StyleProperty — cascade resolution (inline > class+state > class > type+state > type > default)
- [ ] Property inheritance (TextColor, FontSize inherit from parent; Background, Padding do not)
- [ ] DarkTheme, LightTheme — defined as StyleSheets
- [ ] IThemeExtension registry — custom controls register their style rules
- [ ] **Tests:** Drawable intrinsic sizes, StateListDrawable state lookup
- [ ] **Tests:** StyleSheet rule matching (type, class, state, compound), cascade specificity
- [ ] **Tests:** Property inheritance (inherited vs non-inherited properties)
- [ ] **Tests:** Draw invalidation (dirty propagation, NeedsRedraw flag)
- [ ] **UI2Sandbox:** Theme switching (F5), drawable gallery page, stylesheet demo

### Phase 3 — Input + Focus + Debug

- [ ] InputManager — hit testing, mouse routing, capture, double-click, hover tracking
- [ ] FocusManager — focus, tab navigation, focus stack (auto push/pop with PopupLayer)
- [ ] KeyCode, KeyModifiers, MouseButton enums
- [ ] KeyEventArgs, MouseEventArgs, MouseWheelEventArgs, TextInputEventArgs
- [ ] Cursor management (EffectiveCursor walks parent chain)
- [ ] ShortcutManager — global + scoped keyboard shortcuts, owned by UIContext
- [ ] IInputHandler interface — prioritized input handler chaining on views
- [ ] UIDebugDrawSettings — all flags from UI + new UI2 flags (ShowConstraints, ShowFlexInfo, ShowGridLines)
- [ ] UIDebugOverlay — draws bounds, padding, margin, hit target, focus path, constraints
- [ ] **Tests:** Hit testing (nested views, IsHitTestVisible=false, clipping)
- [ ] **Tests:** Focus navigation (tab order, focus stack push/pop)
- [ ] **Tests:** Mouse capture (capture/release, events routed to captured view)
- [ ] **Tests:** ShortcutManager (global shortcut fires, scoped shortcut only fires when in scope, unregister)
- [ ] **Tests:** IInputHandler chaining (first handler consumes, second not called; first passes, second called)
- [ ] **UI2Sandbox:** Debug toggle keys (F2/F3/F4), mouse hover highlight, focus test page

### Phase 4 — Reactive Properties + Basic Controls

- [ ] Property<T> — observable value with Changed event, implicit read conversion
- [ ] Property<T>.BindTo(label, formatter) — one-way binding helper
- [ ] Property<T>.BindTwoWay(editText) — two-way binding with loop guard
- [ ] Button — text, background drawable, ControlState, OnClick, ICommand
- [ ] Label — text, alignment (HAlign/VAlign), word wrap, ellipsis, max lines
- [ ] Panel — background drawable, padding container
- [ ] Separator — orientation, color, thickness
- [ ] Spacer — empty spacing view
- [ ] CheckBox — toggle with text label, OnCheckedChanged
- [ ] RadioButton + RadioGroup — exclusive selection
- [ ] ToggleButton — stateful button with checked background
- [ ] ToggleSwitch — switch with track/knob
- [ ] Slider — value range, step, orientation, drag events
- [ ] ProgressBar — value 0-1, indeterminate mode
- [ ] NumericField — number input with increment/decrement
- [ ] ImageView — image display with ScaleType
- [ ] ColorView — solid color swatch
- [ ] Expander — collapsible container with header
- [ ] **Tests:** Property<T> change notification, implicit conversion, no-change-no-notify
- [ ] **Tests:** Property<T> one-way binding updates label on value change
- [ ] **Tests:** Property<T> two-way binding syncs both directions without loop
- [ ] **Tests:** Button click, CheckBox toggle, RadioGroup selection, Slider value clamping
- [ ] **Tests:** Label measurement (wrap vs no-wrap, ellipsis)
- [ ] **Tests:** Expander expand/collapse changes measured size
- [ ] **UI2Sandbox:** Controls demo page with all basic controls, reactive property demo

### Phase 5 — Text Input

- [ ] TextEditingBehavior — cursor, selection, clipboard, undo/redo (port from UI)
- [ ] UndoStack — edit coalescing, undo/redo (port)
- [ ] ITextEditHost interface
- [ ] EditText — single/multi-line, placeholder, read-only, max length, input filter
- [ ] PasswordBox — masked display
- [ ] EditableLabel — label that becomes EditText on click
- [ ] **Tests:** TextEditingBehavior cursor movement, selection, undo/redo, clipboard
- [ ] **Tests:** EditText input filter, max length, submit event
- [ ] **UI2Sandbox:** Text editing demo page

### Phase 6 — Data Controls

- [ ] ScrollView + ScrollBar + MomentumHelper (port)
- [ ] IModel — unified model interface (RowCount, GetData, HasChildren, OnDataChanged)
- [ ] ModelIndex, ModelRole
- [ ] ListModel<T> — wraps List<T> as flat IModel
- [ ] TreeModel — hierarchical IModel implementation
- [ ] SortingProxyModel — wraps IModel with sorting
- [ ] ViewRecycler (port)
- [ ] ListView — virtualized, uses IModel (flat), fixed/variable height, selection, momentum
- [ ] FlattenedTreeAdapter (port, adapted for IModel)
- [ ] TreeView — virtualized, uses IModel (hierarchical), expand/collapse, indent
- [ ] TabView — tab headers, placement, closable tabs
- [ ] ComboBox — dropdown selection, backed by IModel
- [ ] SelectionModel — single/multi selection (port)
- [ ] GridView — virtualized flowing grid with IModel, fixed cell size, ViewRecycler pooling
- [ ] ListView slow-click rename — SlowClickRenameEnabled, delay threshold, OnSlowClickRename event
- [ ] HierarchicalState — capture/restore expand/collapse, selection, scroll for tree widgets
- [ ] TreeView.CaptureState() / ApplyState() using HierarchicalState
- [ ] **Tests:** IModel RowCount, GetData, HasChildren for flat and hierarchical models
- [ ] **Tests:** ListModel<T> wraps list correctly, OnDataChanged fires on modification
- [ ] **Tests:** SortingProxyModel sorts by column, maintains index mapping
- [ ] **Tests:** ViewRecycler pool/acquire/recycle counts
- [ ] **Tests:** ListView visible range calculation (fixed and variable height)
- [ ] **Tests:** FlattenedTreeAdapter expand/collapse, node count
- [ ] **Tests:** SelectionModel single/multi select, clear
- [ ] **Tests:** GridView visible cell calculation, recycler integration
- [ ] **Tests:** Slow-click rename timing (too fast = no rename, within window = rename, too slow = no rename)
- [ ] **Tests:** HierarchicalState capture/restore roundtrip, merge partial state
- [ ] **UI2Sandbox:** ListView demo (1000 items), GridView demo (thumbnails), TreeView demo, TabView demo, ScrollView demo

### Phase 7 — Overlays + DragDrop + Animation

- [ ] PopupLayer — modal backdrop, click-outside dismissal, auto focus push/pop
- [ ] Dialog — modal, auto-centered, title + content + buttons, DialogResult
- [ ] ContextMenu — popup item list, submenus, separators
- [ ] TooltipManager — show delay, auto-hide, interactive tooltips
- [ ] DragDropManager — Idle/Potential/Active state machine, adorner, IDragSource/IDropTarget
- [ ] DragData, drop effects (None/Copy/Move/Link)
- [ ] AnimationManager — track active animations, cancel for view
- [ ] FloatAnimation, ColorAnimation, Vector2Animation
- [ ] Easing functions (Linear, EaseInQuad, EaseOutQuad, EaseInOutQuad, etc.)
- [ ] Storyboard — parallel animation group
- [ ] ViewAnimator — convenience for animating view properties
- [ ] **Tests:** Dialog show/close/result lifecycle
- [ ] **Tests:** DragDropManager state transitions (idle -> potential -> active -> complete/cancel)
- [ ] **Tests:** Animation update, easing function values, storyboard completion
- [ ] **UI2Sandbox:** Dialog demo, context menu demo, tooltip demo, drag-drop demo, animation demo

### Phase 8 — Toolkit

- [ ] DockManager + DockablePanel + DockSplit + DockTabGroup
- [ ] DockZoneIndicator — visual feedback during dock drag
- [ ] MenuBar — horizontal menu with dropdown items
- [ ] Toolbar + ToolbarButton + ToolbarSeparator
- [ ] StatusBar — bottom status line with sections
- [ ] SplitView — draggable divider between two panels, persistent SplitRatio with PersistenceId
- [ ] BreadcrumbBar — path segments as clickable buttons, OnSegmentClicked event
- [ ] PropertyGrid + editors (Bool, Int, Float, String, Enum, Range, Color, Vector3)
- [ ] DraggableTreeView — TreeView with drag reorder
- [ ] ColorPicker — interactive color selection
- [ ] **Tests:** PropertyGrid editor creation per type
- [ ] **Tests:** DockManager panel add/remove/reparent
- [ ] **Tests:** BreadcrumbBar SetPath creates correct segments, click fires event with index
- [ ] **UI2Sandbox:** Toolkit demo page (docking, property grid, menus, toolbar)

### Phase 9 — Runtime Integration + XML Loading

- [ ] UISubsystem — lifecycle, theme setup, font service, clipboard
- [ ] ScreenUIView — screen-space overlay rendering
- [ ] Shell integration — input dispatch, cursor, DPI
- [ ] XML layout loader — element names → View types (factory registry), attributes → properties + LayoutParams
- [ ] XML id resolution — FindById<T> after load
- [ ] XML styleClass attribute → View.StyleId for stylesheet matching
- [ ] **Tests:** XML loader creates correct view hierarchy from XML string
- [ ] **Tests:** XML attributes map to correct properties and LayoutParams
- [ ] **Tests:** FindById returns correct view after XML load
- [ ] **UI2Sandbox:** Full sandbox running through UISubsystem, XML layout demo page

### Phase 10 — Migration

- [ ] Port UISandbox demos to UI2 (verify feature parity)
- [ ] Port editor to UI2
- [ ] Port tower defense game UI to UI2
- [ ] Remove Sedulous.UI dependency from migrated projects
- [ ] Performance comparison: measure/layout time UI vs UI2
