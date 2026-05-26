# Window System Architecture

## Window Modes

### Sidebar Mode (default)

```
+----------------+------------------------+
|                |                        |
|   Normal       |  Vsplit Window          |  <- Terminal buffer (locked)
|   Windows      |  (winfixwidth=true)     |  <- C-h navigates left
|                |                        |
+----------------+------------------------+
```

**Components:**

- **Normal Windows** — Regular editor windows (left side)
- **Vsplit Window** — Terminal window on the right side with `winfixwidth=true`

**Key properties:**

- Vsplit window: `winfixwidth=true`, positioned on the right side of the editor
- No border, behaves as a native split

### Fullwidth Mode (toggle)

```
+------------------------------------------+
|                                          |
|         Float Window (terminal)          |  <- Centered, rounded border
|         Full editor width                |  <- is_expanded=true
|                                          |
+------------------------------------------+
```

**Behavior:**

- Sidebar -> fullwidth: vsplit closes, float opens centered at full editor width
- Fullwidth -> sidebar: float closes, vsplit is recreated on the right side
- Window navigation keymaps disabled (no other windows to navigate to)

### Float Mode (floating=true)

```
        +--------------------+
        |                    |
        |  Centered Float    |  <- No split
        |  (terminal)        |  <- Rounded border
        |                    |  <- 80% width/height
        +--------------------+
```

**Properties:**

- Centered floating window
- No proxy split
- Border: "rounded"
- Size: 80% of editor width/height

## Window Invariants

1. **Terminal Buffer Lock**: Terminal window MUST NEVER change buffers
2. **Vsplit Layout**: Sidebar mode uses vsplit on the right side with `winfixwidth=true`
3. **Float Geometry**: Fullwidth mode uses centered float with `rounded` border
4. **Fullwidth Toggle**: vsplit closes, float opens (and vice versa)

## Focus Behavior

- **Navigation from float**: `<C-h>` focuses the nearest normal window to the left
- **Float focus management**: Focus stays in float or moves to normal windows; no proxy split to redirect

## Geometry Engine

### Width Calculation

- **Percentage mode** (1-100): `math.floor(editor_width * (width_config / 100))`
- **Absolute mode** (>100): Use value directly

### Content Dimensions

Calculated AFTER geometry is finalized:

- `cols = width - border_offset - (padding * 2)`
- `lines = height - border_offset - row_offset`
- Where `row_offset = 1` when `list_buffer=true`

### Padding

- Left padding: `foldcolumn` set to padding value
- Right padding: `COLUMNS` env var limited to content width

## Source

See also: [module-window.md](module-window.md)
