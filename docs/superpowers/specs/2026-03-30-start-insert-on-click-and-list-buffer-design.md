# Design: `start_insert_on_click` and `list_buffer` options

**Date:** 2026-03-30
**Status:** Approved

---

## Overview

Add two new boolean options to `cli-integration.nvim`:

1. **`start_insert_on_click`** — Forces insert mode when the user clicks inside the integration terminal window.
2. **`list_buffer`** — Makes the terminal buffer appear in the bufferline with the integration name as its label, and adjusts the sidebar window to start one row lower.

Both options are available at the global config level (`Cli-Integration.Config`) and at the per-integration level (`Cli-Integration.Integration`). Per-integration values override the global default.

---

## Option 1: `start_insert_on_click`

### Purpose

When working with a sidebar or floating terminal, clicking on the terminal window while in normal mode does not automatically re-enter insert (terminal) mode. This option makes the terminal immediately responsive to mouse clicks.

### Defaults

- Global default: `false`
- Per-integration default: inherits global

### Behavior

When `start_insert_on_click = true`, two normal-mode keymaps are registered on the terminal buffer in `create_terminal`:

```lua
vim.keymap.set("n", "<LeftMouse>",   "i", { buffer = buf, noremap = true, silent = true })
vim.keymap.set("n", "<2-LeftMouse>", "i", { buffer = buf, noremap = true, silent = true })
```

These keymaps are buffer-local and therefore only fire when the click lands inside the terminal buffer's window. The existing `BufEnter`/`WinEnter` autocmd already calls `startinsert` when entering the terminal from another window, so the `<LeftMouse>` keymap firing `"i"` in that same flow is redundant but harmless. The keymap's primary value is when the user is already in the terminal window in normal mode and clicks to resume typing.

No interaction with the `WinLeave` → `stopinsert` autocmd: clicking inside the terminal window does not trigger `WinLeave`, so there is no race condition.

**Toggle / reopen behaviour:** The keymaps are registered once in `create_terminal` (buffer-local). When the terminal is hidden and reopened via `toggle_terminal` (which calls `create_sidebar_layout` or `create_float_window` but NOT `create_terminal` again), the buffer and its keymaps persist. No re-registration is needed in the layout functions.

Applies to both **sidebar** and **floating** window modes.

### Implementation touchpoints

| File | Change |
|------|--------|
| `lua/cli-integration/config.lua` | Add `start_insert_on_click boolean\|nil` to `Cli-Integration.Integration` and `Cli-Integration.Config` annotations. Add `start_insert_on_click = false` to `M.defaults`. Add `start_insert_on_click = M.options.start_insert_on_click` to the `default_integration` table in `M.setup` (same pattern as `floating`, `border`, etc.). |
| `lua/cli-integration/terminal.lua` | In `create_new_terminal`, inside the `win = { ... }` literal (lines 198–219), add `start_insert_on_click = integration.start_insert_on_click`. |
| `lua/cli-integration/window.lua` | In `create_terminal`, after the `<C-h/j/k/l>` navigation keymaps block, if `opts.win.start_insert_on_click == true`, register the `<LeftMouse>` and `<2-LeftMouse>` keymaps on `buf`. |

---

## Option 2: `list_buffer`

### Purpose

By default, the terminal buffer is hidden from the bufferline (`buflisted = false`). When `list_buffer = true`, the buffer is listed so users can navigate to it via bufferline plugins. The buffer name is set to `[<integration.name>]` (e.g., `[Claude]`). Because bufferline typically occupies the top row, the sidebar window is shifted one row down to avoid overlapping it.

### Defaults

- Global default: `false`
- Per-integration default: inherits global

### Behavior

**Buffer listing:** Applied in `create_terminal` when `opts.win.list_buffer == true`. Both calls must be placed **after** the `nvim_buf_call` block (i.e., after `job_id` is assigned and the buffer has `buftype = "terminal"`). Calling `nvim_buf_set_name` before `termopen`/`jobstart` targets a scratch buffer and the name may be discarded or overridden when the terminal initializes.

```lua
-- After the nvim_buf_call block:
if win_opts.list_buffer then
    vim.bo[buf].buflisted = true
    pcall(vim.api.nvim_buf_set_name, buf, win_opts.buffer_name)
end
```

`nvim_buf_set_name` is wrapped in `pcall` because it may fail on some Neovim versions or if a buffer with the same name already exists. On failure the buffer remains listed with its raw `term://...` name — acceptable.

**`buffers.lua` interaction:** `buffers.get_open_buffers_paths()` filters on `buftype == ""`, so terminal buffers (`buftype = "terminal"`) are never included regardless of `buflisted`. No change needed in `buffers.lua`.

**BufWinEnter guard interaction:** The buffer-switch lock in `create_terminal` prevents non-terminal buffers from entering the terminal window. With `buflisted = true`, the terminal buffer could be navigated to from a normal editor window via `:bnext`/`:bprev` or a bufferline click. In that case the guard does not fire (it only triggers when a non-terminal buffer enters the terminal window). This is acceptable — the user is intentionally navigating to the terminal buffer.

**Sidebar geometry adjustment:**

When `list_buffer = true`, the floating sidebar window is shifted down by 1 row. Applied in `update_sidebar_geometry`, **sidebar branch only** (not expanded):

```lua
local row_offset = data.list_buffer and 1 or 0
-- height already computed as: split_row + split_height - border_offset
height = height - row_offset
-- col is unchanged
vim.api.nvim_win_set_config(float_win, {
    relative = "editor",
    border   = border,
    width    = width,
    height   = height,
    row      = row_offset,  -- 0 normally, 1 when list_buffer
    col      = col,         -- unchanged
})
```

**Expanded (fullwidth) mode:** The row offset is deliberately NOT applied in the expanded branch of `update_sidebar_geometry`. When expanded, the sidebar covers the full editor; the bufferline is not visible. This is an intentional invariant — do not add a row offset to the expanded branch.

**`M.sidebars` data structure:** `create_sidebar_layout` stores `list_buffer` in the sidebar entry:

```lua
M.sidebars[float_win] = {
    split_win    = split_win,
    split_buf    = split_buf,
    terminal_buf = buf,
    width_config = width_config,
    win_opts     = win_opts,
    padding      = padding,
    is_expanded  = false,
    list_buffer  = win_opts.list_buffer or false,  -- NEW
}
```

The comment block documenting `M.sidebars` at the top of `window.lua` (lines 13–21) must also be updated to include the `list_buffer` field.

### Implementation touchpoints

| File | Change |
|------|--------|
| `lua/cli-integration/config.lua` | Add `list_buffer boolean\|nil` to `Cli-Integration.Integration` and `Cli-Integration.Config` annotations. Add `list_buffer = false` to `M.defaults`. Add `list_buffer = M.options.list_buffer` to the `default_integration` table in `M.setup` (same pattern as `floating`, `border`, etc.). |
| `lua/cli-integration/terminal.lua` | In `create_new_terminal`, inside the `win = { ... }` literal, add `list_buffer = integration.list_buffer` and `buffer_name = "[" .. integration.name .. "]"`. |
| `lua/cli-integration/window.lua` | (1) Update `M.sidebars` comment block to add `list_buffer` field. (2) In `create_terminal`: if `opts.win.list_buffer`, set `buflisted = true` and call `pcall(vim.api.nvim_buf_set_name, buf, opts.win.buffer_name)`. (3) In `create_sidebar_layout`: add `list_buffer = win_opts.list_buffer or false` to `M.sidebars[float_win]` entry. (4) In `update_sidebar_geometry`, sidebar branch: compute `row_offset = data.list_buffer and 1 or 0`, subtract from `height`, pass `row = row_offset` to `nvim_win_set_config` (col unchanged). |

---

## Files modified

- `lua/cli-integration/config.lua`
- `lua/cli-integration/terminal.lua`
- `lua/cli-integration/window.lua`

No new files required.
