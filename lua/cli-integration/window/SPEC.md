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
