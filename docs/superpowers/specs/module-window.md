# Module Spec: window.lua

## Overview

Window and terminal lifecycle management. The core module responsible for creating, positioning, and protecting terminal windows.

## Key Data Structures

### `M.sidebars`

Table mapping `sidebar_win` → sidebar data:

```lua
{
  sidebar_win = number,      -- Vsplit window handle (or float in fullwidth mode)
  terminal_buf = number,     -- Terminal buffer handle
  width_config = number,     -- Original width configuration
  padding = number,          -- Horizontal padding in columns
  win_opts = table,          -- Window options
  is_expanded = boolean,     -- Fullwidth mode flag
  list_buffer = boolean,     -- Bufferline listing flag
}
```

### Window Classification Helpers

- `is_integration_sidebar_win(win, term_buf)` — Checks if window is the integration sidebar window
- `is_valid_win(win)` — Checks if window handle is valid
- `find_layout_anchor_window()` — Finds a safe anchor window for creating the vsplit
- `is_terminal_visible(terminal)` — Checks if terminal window is visible

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

Creates vsplit on the right side with terminal buffer. Returns vsplit window handle.

**Steps:**

1. Calculate vsplit width from `width_config` (percentage or absolute)
2. Find anchor window via `find_layout_anchor_window()`
3. Create vsplit via `botright vsplit`
4. Set terminal buffer in the vsplit
5. Configure vsplit (winfixwidth=true, no line numbers, no signcolumn, etc.)
6. Apply padding via foldcolumn
7. Register in `M.sidebars[sidebar_win]`
8. Set up WinClosed cleanup autocmd
9. Set up VimResized/WinResized sync autocmd
10. Enter insert mode (`startinsert`)

### `M.update_sidebar_geometry(sidebar_win, is_expanded, should_focus)`

Handles fullwidth toggle between sidebar vsplit and centered float.

**Expanded mode (fullwidth):**

- Closes vsplit if valid
- Opens centered float with rounded border containing the terminal buffer
- Updates `M.sidebars` to point to the new float window
- Enters insert mode if `should_focus` is true

**Sidebar mode (restore):**

- Closes float if valid
- Creates new vsplit via `create_sidebar_layout()`
- Enters insert mode if `should_focus` is true

### `M.resize_sidebars()`

Bidirectional sync on VimResized/WinResized events.

Distinguishes editor resize (recalculate from `width_config` percentage) from manual split resize (split as source of truth).

## Critical Implementation Details

### Buffer Lock (lines 594-665)

`BufWinEnter` autocmd prevents any buffer except terminal buffer from loading in terminal window:

- **Case 1**: Integration window with different buffer loaded → restore terminal buffer, redirect new buffer to normal window
- **Case 2**: Regular window with terminal buffer loaded → focus integration float if visible

### Vsplit Window (lines 527-600)

The vsplit is created directly with the terminal buffer:

- **Layout**: `botright vsplit` with `winfixwidth=true` on the right side
- **Configuration**: No line numbers, no signcolumn, no cursorline, no spell
- **Cleanup**: `WinClosed` autocmd removes sidebar entry from `M.sidebars`
- **Resize Sync**: `VimResized`/`WinResized` autocmds adjust width proportionally

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
- `calculate_content_dimensions(win, border, padding)` — Usable cols/lines

### Environment Building

`build_job_env(opts, cols, lines)`:

1. Inherit full process env via `vim.fn.environ()`
2. Strip tmux identity vars (`TMUX`, `TMUX_PANE`, `TERM_PROGRAM`, `TERM_PROGRAM_VERSION`) to prevent bracketed-paste leakage
3. Strip Ghostty identity vars (`GHOSTTY_RESOURCES_DIR`, `GHOSTTY_SHELL_FEATURES`, `GHOSTTY_BIN_DIR`, `TERMINFO`) to prevent TUI garbage characters from Ghostty-specific escape sequences
4. Set `COLUMNS`/`LINES` from finalized geometry
5. **Normalize `TERM` to `xterm-256color` and `COLORTERM` to `truecolor` unless explicitly overridden in `opts.env`** — this prevents host terminal-specific terminfo (e.g. Ghostty's `xterm-ghostty`) from emitting escape sequences that Neovim's `:terminal` cannot handle, which appear as visible garbage characters like `?1016$p`
6. Apply optional `env` overrides
7. Apply optional `unset_env` removals

## State Management

- `M.resized_autocmd_setup` — Track if resize autocmd is registered
- `M._last_editor_width` — Track editor width to distinguish resize types

## Source Location

`lua/cli-integration/window.lua` (1003 lines)
