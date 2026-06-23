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
- **Vsplit Window** — Terminal window on the right side with `winfixwidth` set per `dynamic_resize`

**Key properties:**

- Vsplit window: `winfixwidth=true` when `dynamic_resize=false`, `false` when enabled. This prevents Neovim's layout engine from auto-resizing the sidebar when the user resizes the editor.
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

**Height formula:** `vim.o.lines - vim.o.cmdheight - 3`. The `-3` prevents the bottom border from overlapping the statusline. With `border="single"`, the top border is at `row=0`, content starts at `row+1`, and the bottom border is at `row = height + 1`. The formula guarantees `height + 1 < vim.o.lines - vim.o.cmdheight`, leaving the statusline row untouched.

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

- **Splits**: `cols = width - (padding * 2)`, `lines = height`
  - `nvim_win_get_width()` includes foldcolumn, so `padding * 2` accounts for left foldcolumn + right visual margin
- **Floats**: `cols = width`, `lines = height`
  - `nvim_win_get_width()` returns content width (border is outside), padding is always 0

### Padding

- Left padding: `foldcolumn` set to padding value (splits only)
- Right padding: achieved by making PTY width = `window_width - (padding * 2)`, creating a visual margin
- Floats: no padding (no foldcolumn support)

## Height Stability

### CRITICAL: showtabline Pin

The sidebar is a vsplit — it shares the full editor height with other windows. When `showtabline` changes (e.g. bufferline sets it to 2 when files open, 0 when none remain), ALL windows lose/gain 1 row. The sidebar cannot maintain its height because Neovim's layout engine must redistribute the reduced available rows — `nvim_win_set_height` is overridden every time.

**`window/init.lua`** module-level code pins `showtabline = 2` and registers an `OptionSet` autocmd that reverts any override. This prevents bufferline (or any plugin) from fluctuating the value.

**Do not remove or weaken this guard.** Testing showed that:
- Setting `showtabline = 2` once is not enough (bufferline overrides it back)
- Restoring sidebar height via `nvim_win_set_height` is futile (Neovim redistributes after each layout pass)
- Only an `OptionSet` guard that intercepts EVERY change and reverts it works reliably

## Source

See also: [module-window.md](module-window.md)
