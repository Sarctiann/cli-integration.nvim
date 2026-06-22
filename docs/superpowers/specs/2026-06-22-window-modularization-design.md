# Window Modularization Design

## Overview

Transform monolithic `window.lua` (1249 lines) into modular structure under `window/` directory with feature toggles via `config.window_features`.

## Architecture

```
lua/cli-integration/window/
├── init.lua           -- Orchestrator, exports M
├── state.lua          -- M.sidebars, is_integration_window, is_valid_win
├── geometry.lua       -- calculate_width, resize_pty, build_job_env
├── layout.lua         -- create_sidebar_layout, create_float_window
└── features/
    ├── dynamic_resize.lua  -- VimResized, BufReadPost/BufDelete
    ├── fullscreen.lua      -- update_sidebar_geometry, update_float_geometry
    ├── buffer_lock.lua     -- BufWinEnter, WinEnter protection
    ├── insert.lua          -- auto_insert, start_insert_on_click
    └── nav.lua             -- set_nav_keymaps_enabled
```

## Module Responsibilities

### state.lua
- `M.sidebars` table (term_buf → sidebar data)
- `is_integration_window(win, term_buf)` 
- `is_any_integration_win(w)`
- `is_valid_win(win)`

### geometry.lua
- `calculate_width(width_config)` - percentage or absolute
- `calculate_content_dimensions(win, padding)` - usable cols/lines
- `resize_pty(term_buf, win, padding)` - SIGWINCH to terminal
- `build_job_env(opts, cols, lines)` - terminal env with tmux/Ghostty stripping
- `get_geometry(data)` - mode-aware geometry
- `apply_geometry(term_buf)` - apply geometry and resize PTY

### layout.lua
- `create_sidebar_layout(buf, win_opts)` - vsplit terminal on right
- `create_float_window(buf, win_opts)` - centered floating window
- `apply_sidebar_win_opts(win, padding)` - sidebar window options
- `find_layout_anchor_window()` - safe anchor for split creation

### features/dynamic_resize.lua
- VimResized autocmd → resize_sidebars()
- BufReadPost/BufDelete → resize_pty()
- Feature flag: `config.window_features.dynamic_resize`

### features/fullscreen.lua
- `update_sidebar_geometry(term_buf, is_fullscreen, should_focus)`
- `update_float_geometry(term_buf, is_fullscreen, should_focus)`
- Feature flag: `config.window_features.fullscreen`

### features/buffer_lock.lua
- BufWinEnter autocmd - prevent buffer switching
- WinEnter autocmd - restore terminal buffer
- Feature flag: `config.window_features.buffer_lock`

### features/insert.lua
- BufEnter/WinEnter → startinsert
- start_insert_on_click keymap
- Feature flag: `config.window_features.auto_insert` + `config.window_features.start_insert_on_click`

### features/nav.lua
- `set_nav_keymaps_enabled(term_buf, enabled)` - C-h/j/k/l navigation
- Feature flag: `config.window_features.nav_keymaps`

## Feature Detection Pattern

Each feature module:
```lua
local config = require("cli-integration.config")

local M = {}

function M.setup(term_buf, win_opts)
  if config.options.window_features.dynamic_resize == false then
    return false
  end
  -- setup...
  return true
end

return M
```

## Config Schema

```lua
--- @class Cli-Integration.WindowFeatures
--- @field dynamic_resize boolean|nil  -- VimResized sync (default: true)
--- @field fullscreen boolean|nil      -- Fullscreen toggle (default: true)
--- @field buffer_lock boolean|nil     -- Buffer lock autocmds (default: true)
--- @field auto_insert boolean|nil     -- startinsert on WinEnter (default: true)
--- @field nav_keymaps boolean|nil     -- C-h/j/k/l navigation (default: true)
--- @field start_insert_on_click boolean|nil  -- Click to insert (default: true)
```

## Feature Behavior Matrix

| Feature | Enabled (default) | Disabled |
|---------|------------------|----------|
| dynamic_resize | VimResized resizes sidebars | No resize on editor resize |
| fullscreen | Fullscreen toggle works | toggle_fullscreen no-op |
| buffer_lock | BufWinEnter/WinEnter guards | No buffer protection |
| auto_insert | startinsert on enter | No auto insert |
| nav_keymaps | C-h/j/k/l work | No navigation keys |
| start_insert_on_click | Click enters insert | No click-to-insert |

With ALL features disabled: plain terminal in vsplit (or float if `floating=true`).

## API Contract (window/init.lua)

```lua
local M = {}

-- Terminal lifecycle
M.create_terminal(cmd, opts)  -- Create terminal + window + autocmds
M.toggle_terminal(terminal)   -- Toggle visibility
M.is_terminal_visible(terminal) -- Check visibility

-- Geometry
M.apply_geometry(term_buf)
M.resize_pty(term_buf, win, padding)

-- Fullscreen
M.update_sidebar_geometry(term_buf, is_fullscreen, should_focus)
M.update_float_geometry(term_buf, is_fullscreen, should_focus)

-- Navigation
M.set_nav_keymaps_enabled(term_buf, enabled)

-- State
M.sidebars  -- Read-only access to sidebar data
M.resize_sidebars()

return M
```

## Migration Notes

1. `terminal.lua` requires `window` instead of `window.init`
2. `config.lua` adds `window_features` table with typed schema
3. `init.lua` unchanged (just changes require path)
4. `adapters/bufline.lua` stays separate, consumed by layout.lua
