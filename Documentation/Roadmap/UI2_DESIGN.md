# Sedulous.UI - Next-Generation UI Framework Design

## Background: GUI vs UI Comparison

Full comparative analysis of Sedulous.GUI (Deprecated) and Sedulous.UI (Foundation).

### Architecture Overview

| Aspect | Sedulous.GUI (Deprecated) | Sedulous.UI (Foundation) |
|--------|---------------------------|--------------------------|
| Base class | UIElement -> Control -> Container -> Panel | View -> ViewGroup -> layouts |
| Context | GUIContext (670 lines) | UIContext (phase-tracked, multi-window) |
| Layout model | WPF-style Measure(SizeConstraints) -> Arrange(RectangleF) | Android-style MeasureSpec + Gravity |
| Theming | ITheme interface + ControlStyle/StateStyle per type | Flat string->value dictionaries + IThemeExtension |
| Rendering | DrawContext abstraction | UIDrawContext wrapping VGContext |
| Source files | ~132 files, ~35,600 lines | ~122 files (core), ~7,000+ lines core + toolkit/runtime |
| Widget count | 57 controls | ~22 controls + 8 layout types + toolkit components |

### Category Comparison

| Category | GUI | UI | Winner |
|----------|-----|-----|--------|
| Layout system | Good (WPF-style) | Good (Android-style, simpler) | UI |
| Widget breadth | 57 controls | ~22 + toolkit | GUI |
| Widget quality | Decent, no virtualization | Virtualized lists, adapters | UI |
| Theming | Type-safe but rigid | Flat keys, extensible | UI |
| Drawable system | Basic (color + ImageBrush) | Rich composable hierarchy | UI |
| Input handling | Solid | Solid + phase safety + momentum | UI |
| Memory safety | Good (ElementHandle) | Good (ViewId + phase tracking) | UI |
| Data virtualization | None | Full (recycler + adapters) | UI |
| Multi-window | No | Yes | UI |
| Extensibility | Service DI | Theme extensions + adapters + XML | UI |
| Code size / maintainability | ~35.6K lines | ~7K+ core | UI |
| Demos | 18 demos, broad | 9 demos, deeper | UI |

### Verdict

Sedulous.UI is the better framework. It's a deliberate rewrite that learned from GUI's mistakes.
GUI's main strength is widget breadth. UI's decisive advantages are virtualization, the drawable
system, multi-window support, and 5x code reduction. The deprecation is well-justified.

---

## Problems with the Current Android-Inspired Model

### 1. LayoutParams as Separate Objects (Critical)
Every child addition requires heap-allocating a LayoutParams object, and parents must cast to their
specific subclass. This creates ~100+ instances of boilerplate like:
```beef
mLayout.AddView(label, new LinearLayout.LayoutParams() {
    Width = Sedulous.UI.LayoutParams.MatchParent,
    Height = 22
});
```

### 2. Magic Sentinel Values (Moderate)
`MatchParent = -1` and `WrapContent = -2` are magic numbers mixed with pixel values. No type safety.

### 3. LayoutParams Type Mismatch (Moderate)
ViewGroup.AddView() accepts base LayoutParams. Every access in OnMeasure/OnLayout requires
defensive casting: `let llp = child.LayoutParams as LinearLayout.LayoutParams;`

### 4. MeasureSpec Information Loss (Moderate)
Three modes (Unspecified/AtMost/Exactly) are really just a crippled min/max constraint system.

### 5. No Container-Level Distribution (Moderate)
No equivalent of CSS Flex's `justify-content: space-between`. Must use Spacer widgets.

### 6. GridLayout Manual Setup (Moderate)
Requires 5-8 lines of column/row definitions before adding children. No auto-flow.

---

## Layout Models Compared

### Android (current Sedulous.UI)
- MeasureSpec (3 modes) + LayoutParams (per-parent subclass)
- Constraints flow down, sizes flow up, parent arranges
- Problem: information loss, casting, boilerplate

### Flutter BoxConstraints
- `{ minW, maxW, minH, maxH }` constraint struct
- Single unified type replaces MeasureSpec, SizeConstraints, and MatchParent/WrapContent
- MatchParent = tight constraint (min == max == parentSize)
- WrapContent = loose constraint (min = 0, max = parentSize)
- Clean math: just clamping. No modes, no sentinels.

### CSS Flexbox
- flex-grow / flex-shrink / flex-basis per child
- justify-content / align-items on container
- space-between / space-evenly eliminates spacer hacks
- Battle-tested on billions of UIs

### SwiftUI Offer/Choose/Place
- Parent proposes a size, child chooses, parent places
- Simplest mental model
- Weakness: can't express "you must be at least this big" without extra passes

### Qt Size Policies
- External layout managers (separate from widgets)
- Size hints (preferred, minimum, maximum) + Size Policy enum
- 7 policies: Fixed, Minimum, Maximum, Preferred, Expanding, MinimumExpanding, Ignored
- Good idea: distinguishing "can grow" from "wants to grow"
- Bad: overcomplicated, layout/widget hierarchy splits, black-box solver

---

## Recommended Design: Flutter Constraints + CSS Flex Ergonomics + Qt Semantics

Take the best from each model:

| Take from | What | Why |
|-----------|------|-----|
| Flutter | BoxConstraints as measurement primitive | Clean, lossless, trivial math |
| Flutter | Layout hints on the view, not in separate LayoutParams | Eliminates casting, allocation, boilerplate |
| CSS Flex | FlexGrow / FlexShrink / FlexBasis on children | Strictly more powerful than Android's weight |
| CSS Flex | JustifyContent / AlignItems on containers | Eliminates spacer hacks, covers 90% of alignment |
| CSS Grid | Auto-flow for grid children | No manual Row/Column for simple grids |
| SwiftUI | Intrinsic size queries as optional protocol | Useful for text, images |
| Qt | Size policy semantics (simplified to 3) | "Can grow" vs "wants to grow" distinction |
| Qt | addStretch() as first-class concept | Cleaner than Spacer widgets |

### Core Constraint Type

```beef
public struct BoxConstraints
{
    public float MinWidth, MaxWidth;
    public float MinHeight, MaxHeight;

    public this(float minW, float maxW, float minH, float maxH)
        { MinWidth = minW; MaxWidth = maxW; MinHeight = minH; MaxHeight = maxH; }

    public static BoxConstraints Tight(float w, float h) =>
        .(w, w, h, h);
    public static BoxConstraints Loose(float maxW, float maxH) =>
        .(0, maxW, 0, maxH);
    public static BoxConstraints Expand() =>
        .(float.PositiveInfinity, float.PositiveInfinity,
          float.PositiveInfinity, float.PositiveInfinity);

    public BoxConstraints Deflate(Thickness padding) => ...;
    public float ConstrainWidth(float w) => Math.Clamp(w, MinWidth, MaxWidth);
    public float ConstrainHeight(float h) => Math.Clamp(h, MinHeight, MaxHeight);
    public bool IsTight => MinWidth == MaxWidth && MinHeight == MaxHeight;
}
```

### Size Specification (replaces MatchParent/WrapContent sentinels)

```beef
public enum SizeSpec
{
    case Fixed(float px);
    case Match;   // fill parent (tight constraint)
    case Wrap;    // fit content (loose constraint)
}
```

### Layout Hints on View (no separate LayoutParams)

```beef
public class View
{
    // Size specification
    public SizeSpec Width = .Wrap;
    public SizeSpec Height = .Wrap;
    public Thickness Margin;

    // Flex properties (read by Flex parent)
    public float FlexGrow = 0;
    public float FlexShrink = 0;
    public SizeSpec FlexBasis = .Wrap;

    // Grid properties (read by Grid parent)
    public int GridRow = -1;        // -1 = auto-flow
    public int GridColumn = -1;     // -1 = auto-flow
    public int GridRowSpan = 1;
    public int GridColumnSpan = 1;

    // Alignment
    public Gravity Gravity = .None;  // per-child override of parent's AlignItems

    // Core layout method
    public virtual Size2 Layout(BoxConstraints constraints) { ... }
}
```

### Flex Container

```beef
public class Flex : ViewGroup
{
    public enum Direction { Row, Column }
    public enum Justify { Start, End, Center, SpaceBetween, SpaceAround, SpaceEvenly }
    public enum Align { Start, End, Center, Stretch, Baseline }

    public Direction Direction = .Column;
    public Justify JustifyContent = .Start;
    public Align AlignItems = .Stretch;
    public float Spacing = 0;

    public void AddStretch(float weight = 1) { ... }  // Qt-inspired

    // Flex algorithm:
    // 1. Measure inflexible children (FlexGrow == 0)
    // 2. Distribute remaining space by FlexGrow
    // 3. If overflow, shrink by FlexShrink
    // 4. Apply JustifyContent for leftover space
    // 5. Apply AlignItems/Gravity for cross-axis
}
```

### Grid Container

```beef
public class Grid : ViewGroup
{
    public enum TrackSize
    {
        case Fixed(float px);
        case Flex(float weight);
        case Auto;
    }

    public List<TrackSize> Columns;
    public List<TrackSize> Rows;  // optional: auto-creates rows if omitted
    public float RowSpacing = 0;
    public float ColumnSpacing = 0;
    public bool AutoFlow = true;  // auto-assign row/column to children

    // Auto-flow: children without explicit GridRow/GridColumn
    // are placed left-to-right, top-to-bottom automatically
}
```

### Usage Examples

```beef
// Toolbar with spaced buttons
let toolbar = new Flex(.Row) { JustifyContent = .SpaceBetween, AlignItems = .Center };
toolbar.AddView(new Button("Save"));
toolbar.AddView(new Button("Load"));
toolbar.AddView(new Button("Export"));

// Sidebar + content split
let root = new Flex(.Row);
root.AddView(new SidePanel() { Width = .Fixed(250) });
root.AddView(new ContentArea() { FlexGrow = 1 });

// Form grid with auto-flow (no manual row/col)
let form = new Grid(
    columns: .(.Fixed(120), .Flex(1)),
    spacing: 6
);
form.AddView(new Label("Name:"));     // row 0, col 0 (auto)
form.AddView(new EditText());          // row 0, col 1 (auto)
form.AddView(new Label("Email:"));    // row 1, col 0 (auto)
form.AddView(new EditText());          // row 1, col 1 (auto)

// Explicit placement when needed
form.AddView(new Button("Submit") { GridColumn = 1, GridRow = 2 });

// Push item to far end (Qt-inspired stretch)
let header = new Flex(.Row) { Spacing = 8 };
header.AddView(new Label("App Title"));
header.AddStretch(1);
header.AddView(new Button("Settings"));
```

### Qt Size Policy Mapping (Simplified)

Qt's 7 policies reduced to 3 concepts that map onto Flex:

| Concept | Qt equivalent | Flex equivalent | API |
|---------|--------------|-----------------|-----|
| Fixed size | Fixed | flex: 0 0 size | Width = .Fixed(120) |
| Preferred, can flex | Preferred | flex: 0 1 auto | Width = .Wrap (default) |
| Wants extra space | Expanding | flex: 1 1 0 | FlexGrow = 1 |

### Layout Pass

```
Parent computes BoxConstraints for each child
  (based on own constraints, child's Width/Height spec, margins, flex)
  -> Child.Layout(constraints) returns Size2
    -> Parent places child at offset
```

Single pass for most layouts. Two passes for flex (measure inflexible, then distribute).

### Design Decisions

**Layout hints on View (not separate LayoutParams):**
- Pro: Zero boilerplate, no casting, no allocation, no type mismatch
- Con: View carries ~40 extra bytes of layout fields it may not use
- For a game engine, 40 bytes per widget is negligible. The ergonomic win is massive.

**BoxConstraints vs MeasureSpec:**
- BoxConstraints carries full min/max on both axes = no information loss
- MeasureSpec's 3 modes are just special cases of BoxConstraints
- The math is simpler: just clamping instead of switch statements

**Flex instead of LinearLayout + weight:**
- FlexGrow + FlexShrink is strictly more powerful than Android's weight
- JustifyContent eliminates spacer hacks
- AlignItems + per-child Gravity covers all alignment cases

---

## What to Keep from Sedulous.UI

The layout model is the main thing to redesign. These parts of Sedulous.UI are solid and should
be carried forward:

- **UIContext** with phase tracking and deferred mutation queue
- **ViewId-based references** for memory safety
- **Drawable hierarchy** (ColorDrawable, NineSliceDrawable, StateListDrawable, etc.)
- **Theme system** with flat string keys and IThemeExtension
- **InputManager / FocusManager / DragDropManager** architecture
- **ListView virtualization** with ViewRecycler and adapter pattern
- **Multi-window support** with multiple RootViews
- **TextEditingBehavior** as reusable composition
- **Animation system**

## Implementation Priority

1. BoxConstraints + SizeSpec types (foundation)
2. View base with layout hints (replaces LayoutParams)
3. Flex container (replaces LinearLayout, covers 80% of layouts)
4. Grid container with auto-flow (replaces GridLayout)
5. ScrollView integration
6. Port existing widgets (Button, Label, EditText, etc.)
7. Port toolkit components (PropertyGrid, DockManager, etc.)
