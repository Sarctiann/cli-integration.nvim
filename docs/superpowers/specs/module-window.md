# Module Spec: window.lua

## Overview

Window and terminal lifecycle management. The core module responsible for creating, positioning, and protecting terminal windows.

## Key Data Structures

### `M.sidebars`

Table mapping `float_win` → sidebar data:

```lua
{
  split_win = number,      -- Proxy split window handle
  split_buf = number,      -- Proxy split buffer handle
  terminal_buf = number,   -- Terminal buffer handle
  width_config = number,    -- Original width configuration
  padding = number,         -- Horizontal padding in columns
  win_opts = table,         -- Window options
  is_expanded = boolean,    -- Fullwidth mode flag
  list_buffer = boolean,    -- Bufferline listing flag
}
```

### Window Classification Helpers

- `is_sidebar_split_win(win)` — Checks if window is a proxy split
- `is_integration_sidebar_win(win, term_buf)` — Checks if window is integration sidebar
- `is_integration_proxy_split(win, term_buf)` — Checks if window is proxy split for buffer
- `is_integration_window(win, term_buf)` — Checks if window is any integration window

## Public API

### `M.create_terminal(cmd, opts)`

Creates terminal buffer, window, job, and protection autocmds.

**Flow:**

1. Create terminal buffer (`bufhidden=hide`, `buflisted=false`)
2. Set `b:cli_integration_name` buffer variable BEFORE termopen/jobstart
3. Call `create_sidebar_layout()` or `create_float_window()`
4. Start terminal job (jobstart/termopen) with calculated COLUMNS/LINES
5. Re-apply buffer name after termopen (Neovim overwrites it)
6. Set up navigation keymaps (`<C-h/j/k/l>`)
7. Set up BufWinEnter protection autocmd
8. Set up auto-insert autocmd

### `M.create_float_window(buf, win_opts)`

Creates centered floating window. Returns window handle.

### `M.create_sidebar_layout(buf, win_opts)`

Creates proxy split + floating terminal. Returns float window handle.

**Steps:**

1. Create proxy split via `create_proxy_split()`
2. Create floating window over split
3. Register in `M.sidebars[float_win]`
4. Call `M.update_sidebar_geometry()` for correct dimensions
5. Set up WinClosed cleanup autocmd
6. Set up VimResized/WinResized sync autocmd

### `M.update_sidebar_geometry(float_win, is_expanded, should_focus)`

Updates dimensions, handles fullwidth toggle.

**Expanded mode:**

- Closes proxy split
- Expands float to full editor width with rounded border
- Disables window-navigation keymaps

**Sidebar mode:**

- Recreates proxy split if closed
- Re-enables window-navigation keymaps
- Syncs float dimensions from split width

### `M.resize_sidebars()`

Bidirectional sync on VimResized/WinResized events.

Distinguishes editor resize (recalculate from `width_config` percentage) from manual split resize (split as source of truth).

## Critical Implementation Details

### Buffer Lock (lines 594-665)

`BufWinEnter` autocmd prevents any buffer except terminal buffer from loading in terminal window:

- **Case 1**: Integration window with different buffer loaded → restore terminal buffer, redirect new buffer to normal window
- **Case 2**: Regular window with terminal buffer loaded → focus integration float if visible

### Proxy Split (lines 271-393)

Creates empty scratch buffer (`buftype=nofile`, `modifiable=false`):

- **Focus Redirection**: `WinEnter` autocmd redirects focus to float window
- **Navigation Skip**: If moving from float to split (`<C-h>`), detects `prev_win == float_win` and skips to left window
- **Close Redirection**: `QuitPre` autocmd redirects close to float window
- Never loads any buffer content

### Insert Mode Management

- **Auto-enter**: Automatically enters insert mode on `BufEnter`/`WinEnter`
- **Auto-exit**: `WinLeave` autocmd schedules `stopinsert` to ensure Normal mode at destination
- **start_insert_on_click**: Uses `expr=true` keymap + `getmousepos()` to distinguish inside vs outside clicks

### Geometry Engine

Pure helper functions for dimension calculations:

- `compute_fullwidth_geometry()` — Full editor width minus borders
- `compute_sidebar_target_geometry(data, split_win)` — Calculates from split or config
- `apply_float_geometry(float_win, geom)` — Applies geometry to float
- `apply_split_width(split_win, width)` — Sets split width
- `calculate_width(width_config)` — Supports percentage (1-100) or absolute (>100)
- `calculate_content_dimensions(win, border, padding, list_buffer)` — Usable cols/lines

### Environment Building

`build_job_env(opts, cols, lines)`:

1. Inherit full process env via `vim.fn.environ()`
2. Set `COLUMNS`/`LINES` from finalized geometry
3. Apply optional `env` overrides
4. Apply optional `unset_env` removals

## State Management

- `M.resized_autocmd_setup` — Track if resize autocmd is registered
- `M._suppress_stopinsert` — Suppress stopinsert during proxy split recreation
- `M._last_editor_width` — Track editor width to distinguish resize types

## Source Location

`lua/cli-integration/window.lua` (1003 lines)
