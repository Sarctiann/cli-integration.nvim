# Window System Architecture

## Window Modes

### Sidebar Mode (default)

```
+----------------+------------------------+
|                |                        |
|   Normal       |  Float Window          |  <- Terminal buffer (locked)
|   Windows      |  (directo a la derecha)|
|                |                        |
+----------------+------------------------+
```

**Components:**

- **Normal Windows** — Regular editor windows (left side)
- **No aplica (eliminado)**
- **Float Window** — Terminal window positioned on the right side of the editor

**Key properties:**

- Float window: `zindex=45`, `relative="editor"`, `style="minimal"`, anchored to the right edge
- No border by default, "rounded" when expanded

### Fullwidth Mode (toggle)

```
+------------------------------------------+
|                                          |
|         Float Window (terminal)          |  <- Split hidden
|         Full editor width                |  <- Rounded border
|         zindex=45                        |  <- is_expanded=true
|                                          |
+------------------------------------------+
```

**Behavior:**

- Sidebar -> fullwidth: float expands to full editor width
- Fullwidth -> sidebar: float restores to right-side position
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
2. **No Proxy Split**: No background vsplit exists; float is positioned directly
3. **Float Geometry**: Float dimensions and position managed directly by plugin
4. **Fullwidth Toggle**: Float expands to full width or restores to right side

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
