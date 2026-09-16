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
    dynamic_resize = true,       -- Handle WinResized/VimResized
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

## CRITICAL: Height Stability (showtabline) — cooperate with bufferline, don't fight it

The sidebar window height depends on `showtabline` — when it changes, all windows lose/gain 1 row, including the sidebar.

**Do NOT force `vim.o.showtabline` from an `OptionSet` autocmd.** A previous version of this guard reverted every external change back to `2` from inside an `OptionSet showtabline` autocmd. Because the revert happens *within* the same autocmd execution, Neovim treats the resulting set as nested and suppresses firing `OptionSet` again for it — so the revert itself never showed up in logs — but bufferline's `toggle_bufferline()` (bound to its own tabline-redraw path, which runs on nearly every screen redraw, i.e. very frequently while a CLI tool is streaming output) kept trying to hide the tabline and was silently overridden hundreds of times per second. Each forced flip triggers Neovim's global chrome resize for every window in the tab. This was confirmed with the plugin's own debug logging: **675 `showtabline: 2->0` transitions and 0 `0->2` transitions in a 15 second window** — and was the actual cause of a sidebar drifting by 1-2 rows unpredictably while a CLI tool was active.

**The fix**: cooperate instead of overriding. `adapters/bufline.lua:set_always_show(enabled)` flips bufferline's own `config.options.always_show_bufferline` flag while an integration window is open/closed. `toggle_bufferline()` re-reads that flag on every call, so once it's `true` bufferline simply stops wanting to hide the tabline — nothing to fight, no forced-set loop. `set_always_show(true)` replaces the old direct `vim.o.showtabline = 2` calls at sidebar/float creation; `set_always_show(false)` is folded into `adapters/bufline.lua:restore()`, so every "last integration window closed" cleanup path gets it for free.

To diagnose a similar drift in the future: `debug.lua:win_tree_diff(label)` snapshots every window's size/buftype on demand and logs only what changed since the last snapshot — call it around a suspected layout-shrink (before *and* after reacting) to see the full sequence of who actually resized, and in what order, instead of guessing from our own window's numbers alone.

## CRITICAL: Fullscreen Guard

**`keymaps.lua`** and **`terminal.lua`** both check `window_features.fullscreen == false` before registering/executing toggle_fullscreen. The feature flag in `window_features` controls both keymap registration AND the runtime toggle function. If only one path is guarded, the user can still toggle via the other mechanism.

## CRITICAL: winfixwidth is always true

**`layout.lua`**'s `apply_sidebar_win_opts()` sets `vim.wo[win].winfixwidth = true` unconditionally, regardless of `dynamic_resize`.

**Do not tie this to `dynamic_resize` again.** A previous version set `winfixwidth = false` whenever `dynamic_resize = true`, on the theory that Neovim's layout engine needed to be "free" to resize the sidebar for the resize handler to work. This was wrong: `winfixwidth` only blocks Neovim's *automatic* redistribution when a sibling window opens/closes (e.g. Snacks.explorer, a bufferline offset appearing) — it never blocks our own explicit `nvim_win_set_width` calls. With it disabled, opening/closing any unrelated split silently resized the sidebar, which the reactive resize code then had to race to correct — a second, independent source of the window-size instability TUIs running in the sidebar were affected by.

## CRITICAL: resize reacts to WinResized, not guessed events

**`features/dynamic_resize.lua`** reacts to `WinResized`/`VimResized` only. A previous version *also* guessed at layout changes via `BufReadPost`/`BufDelete` plus a 50ms `defer_fn` ("let the layout settle") in a second, near-duplicate resize routine in `window/init.lua`. That guessed timing raced against bufferline/Snacks' own redraw and could apply already-stale dimensions to the PTY — a real source of TUIs rendering with corrupted/leftover content after a resize. It has been removed. `WinResized` fires only *after* Neovim's layout has actually settled, for any reason a window's size changed (manual resize, a sibling split, `showtabline`/`cmdheight`/`laststatus` changing) — there is no case that needs a guessed companion event.

`geometry.lua:resize_pty()` also deduplicates: it remembers the last `(width, height)` actually sent to each job (keyed by `job_id`, cleared on job exit) and skips `jobresize` if nothing changed. This matters because `WinResized` can legitimately fire several times for the same final size as sibling windows settle — many TUI frameworks do a full clear+repaint per `SIGWINCH`, so a rapid duplicate burst is itself a source of visible rendering corruption, not just wasted work.
