# Window System Architecture

## Window Modes

### Sidebar Mode (default)

```
+---------------------+------------------+
|                     |  Proxy Split     |  <- Empty buffer, winfixwidth=true
|   Normal Windows    |  (navigation)    |  <- WinEnter -> redirects to float
|                     |                  |  <- QuitPre -> closes float instead
|                     +------------------+
|                     |                  |
|                     |  Float Window    |  <- Terminal buffer (locked)
|                     |  (terminal)      |  <- zindex=45, covers split area
|                     |                  |  <- BufWinEnter protection
|                     |                  |
+---------------------+------------------+
```

**Components:**

- **Normal Windows** — Regular editor windows (left side)
- **Proxy Split** — Inert vsplit (right side top), never loads content
- **Float Window** — Terminal window (right side bottom), covers proxy split area

**Key properties:**

- Proxy split: `buftype=nofile`, `modifiable=false`, `winfixwidth=true`
- Float window: `zindex=45`, `relative="editor"`, `style="minimal"`
- Border: "none" by default, "rounded" when expanded

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

- Sidebar -> fullwidth: proxy split is closed/hidden, float expands to full width
- Fullwidth -> sidebar: proxy split is recreated, float restores to synchronized geometry
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

1. **Terminal Buffer Lock**: Terminal windows MUST NEVER change buffers
2. **Proxy Split Inert**: Never contains real buffers, never takes focus
3. **Bidirectional Sync**: Split and float maintain synchronized dimensions
4. **No Split Buffer Loading**: Proxy split NEVER loads buffer content
5. **Fullwidth Toggle**: Split hidden in fullwidth, recreated on restore

## Focus Behavior

- **Proxy Split WinEnter**: Redirects focus to float window
- **Proxy Split QuitPre**: Redirects close to float window
- **Navigation from float**: `<C-h>` skips proxy split, focuses left window
- **Click on proxy split**: Redirects to float via dynamic lookup

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
