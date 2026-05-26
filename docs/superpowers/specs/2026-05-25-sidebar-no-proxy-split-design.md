# Sidebar Refactor: Remove Proxy Split

## Overview

Remove the proxy split (background vsplit) from the sidebar layout. The float window is positioned directly on the right side of the editor without needing an artificial navigation split.

## Main Changes

### 1. Window Structure

**Before:**
```
+----------------+------------------+
|                |  Proxy Split     |  <- Empty buffer, winfixwidth=true
|   Normal       |  (navigation)   |  <- WinEnter -> redirects to float
|   Windows      +------------------+
|                |  Float Window    |  <- Terminal buffer (locked)
+----------------+------------------+
```

**After:**
```
+----------------+------------------------+
|                |                        |
|   Normal       |  Float Window          |  <- Terminal buffer (locked)
|   Windows      |  (positioned on the right side)|
|                |                        |
+----------------+------------------------+
```

The float uses `col = vim.o.columns - float_width` to position on the right edge.

### 2. Navigation

- **C-h from float**: `wincmd h` goes to the left neighbor (window to the left of the float)
- **C-l from float**: `wincmd l` goes to the right neighbor (or stays if no more windows)
- **C-j/k**: same as before (up/down)
- The float has zindex=45 to layer above other floating windows

### 3. Fullwidth Toggle

Same behavior preserved:
- Sidebar -> fullwidth: float expands to full editor width (col=0, width=editor_width)
- Fullwidth -> sidebar: float restores to configured width on the right side

No more split to close/open - only the float geometry changes.

### 4. Simplified M.sidebars

**Before:**
```lua
M.sidebars[float_win] = {
  split_win = number,
  split_buf = number,
  terminal_buf = number,
  width_config = number,
  padding = number,
  win_opts = table,
  is_expanded = boolean,
  list_buffer = boolean,
}
```

**After:**
```lua
M.sidebars[float_win] = {
  terminal_buf = number,
  width_config = number,
  padding = number,
  win_opts = table,
  is_expanded = boolean,
  list_buffer = boolean,
}
```

### 5. Removed Functions

- `create_proxy_split()` - completely removed
- `ensure_split_inert()` - completely removed
- `is_sidebar_split_win()` - removed
- `is_integration_proxy_split()` - removed
- `apply_split_width()` - removed (no split to resize)

### 6. Modified Functions

- `create_sidebar_layout()` - removes proxy split creation, uses float directly
- `update_sidebar_geometry()` - removes split logic, only float geometry
- `resize_sidebars()` - removes split sync, only float resize
- `compute_sidebar_target_geometry()` - removes split as reference

### 7. Removed Autocommands

- WinEnter on split_buf to redirect to float - removed
- QuitPre on split_buf to close float - removed
- WinClosed cleanup for split - simplified (only cleans M.sidebars)

## Files to Modify

1. `lua/cli-integration/window.lua` - main logic
2. `docs/superpowers/specs/window-system-architecture.md` - update diagram
3. `docs/superpowers/specs/module-window.md` - update if necessary
4. `README.md` - remove proxy split references
5. `AGENTS.md` - update constraints if necessary

## Preserved Behavior

- Buffer lock (BufWinEnter protection)
- C-h/j/k/l navigation from terminal
- start_insert_on_click
- list_buffer
- auto_close
- Padding (foldcolumn)
- Resize handling (editor resize recalculates from width_config)