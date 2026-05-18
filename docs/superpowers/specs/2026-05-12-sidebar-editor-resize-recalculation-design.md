# Design: Sidebar Width Recalculation on Editor Resize

**Date:** 2026-05-12  
**Status:** Approved  
**File affected:** `lua/cli-integration/window.lua`

---

## Problem

When Neovim is resized (`VimResized`), `M.resize_sidebars()` uses the observed split width as the source of truth. Since the split width doesn't change when the editor is resized (only when the user manually drags it), the Integration Window and Background Split maintain their previous absolute width instead of recalculating from the configured percentage (`width_config`).

**Effect:** A sidebar configured at 34% (default) stays at its old absolute pixel width after editor resize instead of tracking 34% of the new editor width.

---

## Goal

When the editor is resized, the Integration Window (float) and Background Split must both recalculate their width from `width_config` (respecting percentage vs. absolute distinction). Manual split resize behavior must remain unchanged.

---

## Approach: Distinguish Editor Resize vs. Manual Split Resize

### New module-level state

```lua
M._last_editor_width = vim.o.columns  -- initialized at module load
```

### Decision logic in `resize_sidebars()`

At the top of `resize_sidebars()`:

```lua
local editor_resized = vim.o.columns ~= M._last_editor_width
if editor_resized then
    M._last_editor_width = vim.o.columns
end
```

For each sidebar entry:

- **`is_expanded = true` (fullwidth mode):** Always recalculate from `compute_fullwidth_geometry()` — unchanged from current behavior.
- **`is_expanded = false` (sidebar mode) + `editor_resized = true`:** Recalculate width from `calculate_width(data.width_config)`, subtract padding, apply to both split and float.
- **`is_expanded = false` (sidebar mode) + `editor_resized = false`:** Use observed split width as source of truth (current behavior — handles manual resize).

### Key invariants preserved

| Invariant | Status |
|---|---|
| Split width always matches float width in sidebar mode | ✅ Both updated together from `width_config` on editor resize |
| Manual split resize syncs to float | ✅ `editor_resized = false` branch unchanged |
| Fullwidth toggle unaffected | ✅ Separate `is_expanded` branch |
| Buffer lock (BufWinEnter) unaffected | ✅ No changes to buffer/window protection logic |
| Proxy split never takes focus | ✅ No changes to WinEnter autocmds |
| Bidirectional sync invariant preserved | ✅ Editor resize → both windows; manual resize → float follows split |

### Edge case: VimResized + WinResized fire together

Neovim may fire both events on editor resize. Since `M._last_editor_width` is updated on the first call, the second call will find `columns == _last_editor_width` and fall into the manual-resize branch. This is safe — on the second call, split and float are already synchronized.

---

## Implementation Plan (for writing-plans)

### Step 1 — Initialize `M._last_editor_width`

Add after existing module-level flags (near `M.resized_autocmd_setup`):

```lua
M._last_editor_width = vim.o.columns
```

### Step 2 — Refactor `resize_sidebars()`

Replace the current sidebar-mode branch with the discriminated logic:

```lua
function M.resize_sidebars()
    local editor_resized = vim.o.columns ~= M._last_editor_width
    if editor_resized then
        M._last_editor_width = vim.o.columns
    end

    for float_win, data in pairs(M.sidebars) do
        if is_valid_win(float_win) then
            local is_expanded = not is_valid_win(data.split_win)

            if is_expanded then
                -- Fullwidth: always recompute
                local geom = compute_fullwidth_geometry()
                apply_float_geometry(float_win, geom)
            elseif editor_resized then
                -- Editor resize: recalculate from width_config percentage
                local padding = data.padding or 0
                local configured_width = calculate_width(data.width_config)
                local target_width = configured_width - (padding * 2)
                local border = data.win_opts and data.win_opts.border or "none"
                local border_offset = (border == "none" or border == "") and 0 or 2
                local geom = {
                    width = target_width,
                    height = vim.o.lines - vim.o.cmdheight - border_offset - 1,
                    col = vim.o.columns - target_width,
                    row = 0,
                    border = border,
                }
                apply_split_width(data.split_win, target_width)
                apply_float_geometry(float_win, geom)
            else
                -- Manual split resize: use observed split width as source of truth
                local geom = compute_sidebar_target_geometry(data, data.split_win)
                apply_float_geometry(float_win, geom)
                apply_split_width(data.split_win, geom.width)
            end
        else
            M.sidebars[float_win] = nil
        end
    end
end
```

> Note: The `editor_resized` branch intentionally does **not** call `compute_sidebar_target_geometry()` because that function uses the observed split width as source of truth — which defeats the purpose. Instead, it calls `calculate_width(data.width_config)` directly.

---

## Files Modified

- `lua/cli-integration/window.lua` — only `resize_sidebars()` and module-level state

## Files NOT Modified

- All other modules remain unchanged
- No changes to autocmd registration logic (the existing `VimResized`/`WinResized` autocmd already calls `M.resize_sidebars()` — no new autocmd needed)

---

## Testing Checklist

1. **Editor resize with percentage width:** Resize Neovim → float and split both resize proportionally
2. **Editor resize with absolute width (>100):** Resize Neovim → float and split maintain absolute width (height still recalculates)
3. **Manual split resize:** Drag split → float syncs; subsequent editor resize should snap back to `width_config` percentage
4. **Fullwidth mode on editor resize:** Float stays full-width with correct dimensions
5. **Multiple sidebars open:** All resize independently and correctly
6. **Rapid resize:** No errors, no window invalidation
7. **VimResized + WinResized together:** No double application, no flicker
