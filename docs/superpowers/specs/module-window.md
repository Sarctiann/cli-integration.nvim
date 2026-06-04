# Module Spec: window.lua

## Overview

Window and terminal lifecycle management. The core module responsible for creating, positioning, and protecting terminal windows.

## Key Data Structures

### `M.sidebars`

Table mapping `term_buf` → sidebar data (stable key across toggles):

```lua
{
  term_buf              = number,        -- stable key (never changes)
  mode                  = string,        -- "sidebar" | "float" | "fullscreen"
  origin                = string,        -- "sidebar" | "float" (never changes)
  sidebar_win           = number|nil,    -- vsplit handle (hidden when fullscreen)
  float_win             = number|nil,    -- float handle (active when fullscreen or float origin)
  float_original        = table|nil,     -- saved float config for float-origin restore
  fullscreen_autocmd_id = number|nil,    -- autocmd id of WinClosed guard on fullscreen float
  width_config          = number,
  win_opts              = table,
  padding               = number,
  list_buffer           = boolean,
}
```

### Window Classification Helpers

- `is_integration_window(win, term_buf)` — Checks if window is an integration window (sidebar or float) for a given terminal buffer
- `is_valid_win(win)` — Checks if window handle is valid
- `resize_pty(term_buf, win, padding)` — Resizes terminal job pty to match window content dimensions
- `find_layout_anchor_window()` — Finds a safe anchor window for creating the vsplit
- `is_terminal_visible(terminal)` — Checks if terminal window is visible

## Public API

### `M.create_terminal(cmd, opts)`

Creates terminal buffer, window, job, and protection autocmds.

**Flow:**

1. Create terminal buffer (`bufhidden=hide`, `buflisted=false`)
2. Set `b:cli_integration_name` buffer variable BEFORE termopen/jobstart
3. Call `create_sidebar_layout()` or `create_float_window()`
4. Calculate content dimensions via `calculate_content_dimensions(win, padding)` (padding=0 for floats)
5. Start terminal job (jobstart/termopen) with calculated COLUMNS/LINES
6. Call `resize_pty(buf, win, padding)` to align PTY with calculated dimensions
7. Re-apply buffer name after termopen (Neovim overwrites it)
8. List buffer in bufferline if configured
9. Set up navigation keymaps (`<C-h/j/k/l>`)
10. Set up BufWinEnter protection autocmd
11. Set up auto-insert autocmd

### `M.create_float_window(buf, win_opts)`

Creates centered floating window. Returns window handle.

### `M.create_sidebar_layout(buf, win_opts)`

Creates vsplit on the right side with terminal buffer. Returns vsplit window handle.

**Steps:**

1. Calculate vsplit width from `width_config` (percentage or absolute) — vsplit width equals configured width (padding renders inside via foldcolumn)
2. Find anchor window via `find_layout_anchor_window()`
3. Create vsplit via `botright vsplit`
4. Set terminal buffer in the vsplit
5. Configure vsplit (winfixwidth=true, no line numbers, no signcolumn, etc.)
6. Apply padding via foldcolumn
7. Register in `M.sidebars[term_buf]`
8. Set up WinClosed cleanup autocmd
9. Set up VimResized/WinResized sync autocmd
10. Enter insert mode (`startinsert`)

### `M.update_sidebar_geometry(term_buf, is_fullscreen, should_focus)`

Handles fullscreen toggle for sidebar-origin integrations.

**Parameter change:** First parameter is now `term_buf` (not `sidebar_win`).

**Expanded mode (fullscreen):**

- Collapses vsplit to width 1
- Opens fullscreen float covering full editor width with single border
- **Height formula**: `height = vim.o.lines - vim.o.cmdheight - 3` — the `-3` ensures the bottom border (at `row = height + 1`) does not overlap the statusline (`row = lines - cmdheight - 1`). With border, `nvim_open_win` positions the top border at `row=0`, content starts at `row+1`. Content is `height` rows; bottom border is at `row = height + 1`. The formula guarantees `height + 1 < lines - cmdheight`, leaving the statusline row clear.
- Updates `data.float_win` and `data.mode = "fullscreen"` in-place
- Registers `WinClosed` guard on float, stores autocmd id in `data.fullscreen_autocmd_id`
- **Resizes pty via `resize_pty(term_buf, new_win, 0)`** (fullscreen float has no foldcolumn)

**Sidebar mode (restore):**

- Deletes `WinClosed` guard via `nvim_del_autocmd(data.fullscreen_autocmd_id)`
- Closes float
- Restores vsplit to configured width (no padding discount)
- **Resizes pty via `resize_pty(term_buf, sidebar_win, data.padding)`**

### `M.update_float_geometry(term_buf, is_fullscreen, should_focus)`

Handles fullscreen toggle for float-origin integrations.

**Expanded mode (fullscreen):**

- Saves current float config in `data.float_original`
- Resizes float to full editor coverage via `nvim_win_set_config` with `height = vim.o.lines - vim.o.cmdheight - 3` (same formula as `update_sidebar_geometry` fullscreen branch — see above for rationale)
- Sets `data.mode = "fullscreen"`
- **Resizes pty via `resize_pty(term_buf, float_win, 0)`** (floats have no foldcolumn)

**Float mode (restore):**

- Restores float config from `data.float_original`
- Sets `data.mode = "float"`
- **Resizes pty via `resize_pty(term_buf, float_win, 0)`**

### `M.set_nav_keymaps_enabled(term_buf, enabled)`

Enables or disables `<C-h/j/k/l>` window navigation keymaps (modes `t` and `n`) for a terminal buffer. Called after every fullscreen toggle.

- `enabled = true`: restores wincmd navigation
- `enabled = false`: maps keys to `<Nop>` (no other windows to navigate to in fullscreen)

### `M.resize_sidebars()`

Bidirectional sync on VimResized/WinResized events.

Distinguishes editor resize (recalculate from `width_config` percentage) from manual split resize (split as source of truth).

**After any dimension change** (fullscreen float resize or sidebar vsplit resize), calls `resize_pty()` to send SIGWINCH to the terminal job so TUI apps update their internal size.

- **Fullscreen float**: `resize_pty(term_buf, float_win, 0)` — no foldcolumn; height formula `vim.o.lines - vim.o.cmdheight - 3`
- **Sidebar vsplit**: `resize_pty(term_buf, sidebar_win, data.padding)` — accounts for foldcolumn

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

- `calculate_width(width_config)` — Supports percentage (1-100) or absolute (>100)
- `calculate_content_dimensions(win, padding)` — Usable cols/lines; subtracts `padding * 2` from window width (foldcolumn left + visual margin right). For floats, padding is always 0.
- `resize_pty(term_buf, win, padding)` — Sends SIGWINCH with calculated content dimensions. For floats, padding is always 0.

### Content Dimension Semantics

**`window_width` = total panel width on screen.** The vsplit is created at this exact width. Padding is rendered inside the panel:

- Left: `foldcolumn` set to `padding` value
- Right: PTY width is `window_width - (padding * 2)`, creating a visual margin

For floats, `nvim_win_get_width()` returns content width (border is outside), so padding is always 0 and PTY width equals window width.

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

`lua/cli-integration/window.lua` (1168 lines)
