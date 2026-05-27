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

### Fullscreen Mode (toggle)

**Sidebar origin:**

```
+------------------------------------------+
|                                          |
|         Float Window (terminal)          |  <- Full editor coverage, single border
|         Full editor width                |  <- mode="fullscreen", origin="sidebar"
|                                          |  <- vsplit is hidden (not closed)
+------------------------------------------+
```

**Float origin:**

```
+------------------------------------------+
|                                          |
|         Float Window (terminal)          |  <- Full editor coverage, single border
|         Full editor width                |  <- mode="fullscreen", origin="float"
|                                          |  <- same float, resized in-place
+------------------------------------------+
```

**Behavior:**

- Sidebar → fullscreen: vsplit hides (`nvim_win_hide`), float opens
- Fullscreen → sidebar: float closes, vsplit restores to layout
- Float → fullscreen: same float resizes to full editor coverage
- Fullscreen → float: same float restores original dimensions
- Window navigation keymaps disabled in fullscreen (no other windows visible)

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
- Standalone float (no vsplit)
- Border: "rounded"
- Size: 80% of editor width/height

## Window Invariants

1. **Terminal Buffer Lock**: Terminal window MUST NEVER change buffers
2. **Vsplit Layout**: Sidebar mode uses vsplit on the right side with `winfixwidth=true`
3. **Fullscreen Float**: Fullscreen mode uses a float covering the full editor width with single border
4. **Fullscreen Toggle**: Vsplit is hidden (not closed) in fullscreen; restored on toggle back
5. **Float Toggle**: Float resizes in-place for float-origin integrations

## Focus Behavior

- **Navigation from float**: `<C-h>` focuses the nearest normal window to the left
- **Float focus management**: Focus stays in float or moves to normal windows; no intermediate vsplit for navigation

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
