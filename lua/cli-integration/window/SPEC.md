# Window Module Specification

## Overview

The `window` module manages terminal windows for cli-integration plugin. It supports sidebar, float, and fullscreen modes with optional features.

## Structure

- `init.lua` - Main orchestrator
- `state.lua` - State management (M.sidebars)
- `geometry.lua` - Geometry calculations and PTY resize
- `layout.lua` - Window layout creation
- `features/` - Optional features
  - `dynamic_resize.lua` - Editor resize handling
  - `fullscreen.lua` - Fullscreen toggle
  - `buffer_lock.lua` - Buffer protection
  - `insert.lua` - Auto insert mode
  - `nav.lua` - Navigation keymaps

## Configuration

```lua
require("cli-integration").setup({
  window_features = {
    dynamic_resize = true,       -- Handle VimResized
    fullscreen = true,           -- Fullscreen toggle
    buffer_lock = true,          -- Protect terminal buffer
    auto_insert = true,          -- Auto startinsert
    nav_keymaps = true,          -- C-h/j/k/l navigation
    start_insert_on_click = true, -- Click to insert
  },
})
```

## Feature Behavior

When ALL features are disabled, the window is a plain terminal in a vsplit (or float if `floating=true`).

## CRITICAL: Height Stability (showtabline)

The sidebar window height depends on `showtabline` — when it changes (e.g. bufferline toggles it 0↔2 when buffers open/close), all windows lose/gain 1 row, including the sidebar.

**`window/init.lua`** sets `vim.o.showtabline = 2` at module load AND registers an `OptionSet` autocmd that reverts any change away from 2. This prevents bufferline (or any plugin) from fluctuating the value.

**Do NOT remove or weaken this guard.** If `showtabline` is allowed to change, the sidebar height will oscillate by 1 row every time buffers open/close, and `nvim_win_set_height` cannot fix it because Neovim's layout engine must redistribute the reduced available rows.

## CRITICAL: Fullscreen Guard

**`keymaps.lua`** and **`terminal.lua`** both check `window_features.fullscreen == false` before registering/executing toggle_fullscreen. The feature flag in `window_features` controls both keymap registration AND the runtime toggle function. If only one path is guarded, the user can still toggle via the other mechanism.

## CRITICAL: winfixwidth Tied to dynamic_resize

In **`layout.lua`**, `winfixwidth` is set to `true` when `window_features.dynamic_resize == false`. This prevents Neovim's layout engine from auto-resizing the sidebar on editor resize. When `dynamic_resize = true`, `winfixwidth = false` so the `VimResized` handler can re-apply the configured width.

This is intentional: `dynamic_resize = false` means "don't resize on editor resize", which requires Neovim to leave the sidebar alone. `winfixwidth = true` achieves that at the native level.
