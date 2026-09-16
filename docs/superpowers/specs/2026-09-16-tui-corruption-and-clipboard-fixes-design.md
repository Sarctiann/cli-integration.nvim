# Spec: TUI Corruption, Window Drift, and Clipboard "Ghost Text" Fixes

**Date:** 2026-09-16
**Status:** Implemented
**Context:** Neovim + cli-integration.nvim plugin, running inside tmux, with `adapters.bufferline = true`

---

## 1. Problem Statement

Three related, initially-separate-looking symptoms were reported while running CLI tools (opencode, Claude) inside the plugin's integration window:

1. **Clipboard "ghost text"**: selecting text with the mouse inside the integration window (Neovim `:terminal`, itself inside tmux) sometimes left literal base64-looking garbage at the cursor position instead of copying to the clipboard. Only reproduced with the specific nesting: tmux → Neovim `:terminal` → CLI tool. Did not reproduce with either layer alone.
2. **TUI rendering corruption ("dead text")**: after certain layout changes (manual resize, a sibling split opening/closing, bufferline's tabline appearing/disappearing, fullscreen toggle), the CLI tool's TUI would render stale/leftover lines, as if it had been resized incorrectly. Toggling fullscreen twice reliably "fixed" the corruption, which pointed at the resize pipeline rather than the CLI tool itself.
3. **Sidebar window drift**: the integration window's height would visibly shift by 1-2 rows during normal use (e.g. opening a file from Snacks.explorer), independent of any legitimate layout change (bufferline stayed hidden the whole time by the user's own observation).

All three turned out to be independent bugs discovered by peeling back layers of the same investigation, not variations of one root cause.

## 2. Root Cause 1: OSC 52 clipboard wrapped for the wrong terminal

**Mechanism:** the plugin already stripped `TMUX`/`TMUX_PANE` from the job's environment in `window/geometry.lua:build_job_env()`, specifically to prevent this exact issue — but `jobstart()`/`termopen()`'s `env` option only *extends* the inherited environment (see `:h jobstart-options`); it does not replace it. Without `clear_env = true`, deleting a key from the `env` table you pass has no effect — the child process still inherits the real `$TMUX` from Neovim's own process environment.

With `$TMUX` visible, the CLI tool (correctly, for a *real* tmux parent) wraps its OSC 52 clipboard write in tmux's DCS passthrough envelope (`ESC P tmux; ... ESC \`) on mouse-copy. But its immediate terminal is not tmux — it's Neovim's own `:terminal` emulator (libvterm), which has no special handling for that envelope and renders the raw bytes as literal text.

**Fix:** `window/init.lua` now passes `clear_env = true` in `job_opts`, so the environment `build_job_env()` already constructs (full inherited environment minus the stripped identity vars, plus overrides) becomes the child's *entire* environment instead of merely extending the real one.

## 3. Root Cause 2: guessed resize events + inverted `winfixwidth`

Two independent problems compounded:

1. **`layout.lua`'s `apply_sidebar_win_opts()`** set `winfixwidth = true` only when `window_features.dynamic_resize == false` — i.e., by default (`dynamic_resize = true`) the sidebar was `winfixwidth = false`, leaving it open to Neovim's automatic layout redistribution whenever a sibling window opened or closed (Snacks.explorer, a bufferline offset appearing). This was based on a mistaken assumption: `winfixwidth` only blocks *automatic* redistribution, never our own explicit `nvim_win_set_width` calls, so there was never a reason to disable it.
2. **`window/features/dynamic_resize.lua`** reacted to `VimResized` only (whole-editor resize), while a *second*, near-duplicate resize routine in `window/init.lua` (`resize_all_sidebars`) reacted to `BufReadPost`/`BufDelete` with a `vim.defer_fn(..., 50)` "to let the layout settle" as a heuristic for "a panel probably opened/closed". This guessed timing raced against bufferline/Snacks' own redraw and could apply the PTY resize with already-stale window dimensions — the CLI tool would then be told the wrong size and its next redraw showed leftover content.

**Fix:**
- `winfixwidth` is now unconditionally `true`.
- Both guessed-event resize routines were removed and replaced with a single handler on `WinResized` (+ `VimResized` for completeness), which Neovim only fires *after* a window's size has genuinely changed and the layout has settled — no heuristic, no timer needed.
- `geometry.lua:resize_pty()` now caches the last `(width, height)` sent per `job_id` and skips `jobresize` (SIGWINCH) when nothing changed, since `WinResized` can legitimately fire multiple times for the same final size as sibling windows settle, and a rapid duplicate-SIGWINCH burst is itself a source of visible corruption in TUIs that do a full clear+repaint per resize (confirmed in logs: 3 `WinResized` fires for a single file-open, all resolving to the same dimensions).

## 4. Root Cause 3: fighting bufferline over `showtabline`

The pre-existing "fix" for sidebar height stability was an `OptionSet showtabline` autocmd in `window/init.lua` that reverted any change back to `2`, on the theory that bufferline (or Neovim) might otherwise flip it and shrink every window by a row.

This created a hidden feedback loop instead of preventing one. `bufferline.nvim` (with the common LazyVim default `always_show_bufferline = false`) recomputes visibility and sets `showtabline` on **every tabline redraw**, not just on buffer add/remove — and while a CLI tool is streaming output, Neovim redraws very frequently. Each time bufferline decided to hide the tabline (`2 -> 0`), our autocmd reverted it (`0 -> 2`) from *inside* that same `OptionSet` callback — which Neovim treats as a nested trigger and suppresses firing `OptionSet` autocmds for, so the revert was invisible to any logging, yet it still forced a full chrome-driven resize of every window in the tab each time.

This was confirmed empirically with the plugin's own debug logging enabled: over a 15 second window with a CLI tool actively streaming, **675 `showtabline: 2->0` transitions were logged and 0 `0->2` transitions** — hundreds of forced global-chrome resizes per session, each one a chance for the sidebar to end up a row off from where it started.

**Fix:** stop fighting the symptom (the option) and cooperate with the actual decision-maker. `adapters/bufline.lua` gained `M.set_always_show(enabled)`, which flips bufferline's *own* `config.options.always_show_bufferline` flag while an integration window is open. Since `toggle_bufferline()` re-reads that flag on every call, bufferline itself simply stops wanting to hide the tabline — there is nothing left to override.

- `set_always_show(true)` replaces the old direct `vim.o.showtabline = 2` assignments at sidebar/float creation (`layout.lua`).
- `set_always_show(false)` was folded into `adapters/bufline.lua:restore()`, which already ran at every "last integration window closed" cleanup site — so all three existing call sites got the fix without individual changes.
- The `OptionSet showtabline` autocmd and its `ensure_showtabline_while_active()` helper were deleted from `window/init.lua`.

## 5. New diagnostic tooling (kept for future use)

Added to `debug.lua` (all gated behind `config.options.debug`, zero cost when disabled):

- `M.win_tree_diff(label)` — snapshots every window in the tabpage (size, buftype, filetype, buffer name) and logs only what changed since the last snapshot. Wired into `WinResized`/`VimResized` (before *and* after reacting), `WinNew`/`WinClosed`, `WinEnter`, `BufEnter`, and file open/close autocmds. This is what let us tell apart "Neovim's own layout settling" from "our own reactive code causing further movement", and rule out several third-party plugins (Snacks.explorer, LazyVim dashboard) as innocent.
- `debug_global_chrome_option_set` — logs every change to `showtabline`/`cmdheight`/`laststatus` with a stack trace. This is what surfaced the 675-transition storm.
- `resize_pty_skipped_dedup` — logs when the new size-cache in `resize_pty()` skips a redundant `jobresize`, to make it possible to rule the cache out as itself hiding a needed resize.

**Use these before adding a new reactive guard.** A guessed-event heuristic or an option-forcing autocmd both looked like reasonable fixes at the time they were written; both were the actual bugs. Get a `win_tree_diff` trace of the real sequence first.

## 6. Files Changed

- `lua/cli-integration/window/init.lua` — `clear_env = true`; removed `resize_all_sidebars`/`deferred_resize`/`ensure_buf_autocmd` (guessed-event resize) and `ensure_showtabline_while_active`/`OptionSet showtabline` (the fight loop); removed now-dead `_last_pty_*`/`_last_win_*`/`_pty_resize_pending` state writes.
- `lua/cli-integration/window/geometry.lua` — `resize_pty()` gained a per-`job_id` size dedup cache and `forget_job()`.
- `lua/cli-integration/window/layout.lua` — `winfixwidth = true` unconditional; `vim.o.showtabline = 2` direct sets replaced with `adapters.bufline.set_always_show(true)`; removed dead `_last_pty_*`/`_pty_resize_pending` state.
- `lua/cli-integration/window/features/dynamic_resize.lua` — single `WinResized`/`VimResized` handler, replacing the `VimResized`-only + column/line-change-detection version.
- `lua/cli-integration/window/features/fullscreen.lua` — removed dead `_last_win_*`/`_last_pty_*` writes.
- `lua/cli-integration/window/state.lua` — removed the now-unused fields from the `SidebarEntry` type annotation.
- `lua/adapters/bufline.lua` — added `M.set_always_show(enabled)`; folded `set_always_show(false)` into `M.restore()`.
- `lua/cli-integration/debug.lua` — added `M.win_tree_diff()`, the `showtabline`/`cmdheight`/`laststatus` `OptionSet` watcher, and wired both into the existing debug autocmds.

## 7. Test Plan (manual — this plugin has no automated test suite)

For each of the three original repro scenarios, with `debug = true`:

1. Select/copy text with the mouse inside the integration window while inside tmux — confirm no literal escape/base64 text appears, and the system clipboard actually receives the selection.
2. Trigger each layout-changing action in turn (manual resize, bufferline offset appearing/disappearing, opening/closing a side panel, fullscreen toggle) and confirm the CLI tool's TUI redraws cleanly with no leftover content.
3. Reproduce the dashboard → new file → explorer → integration window → open file sequence and confirm the sidebar height does not drift.
4. Inspect `cli-integration-debug.log`: `debug_global_chrome_option_set` should show at most one `showtabline` transition per genuine open/close of the last integration window, never a rapid burst; `resize_pty` (non-skipped) should fire only when the sidebar's own dimensions actually changed.

Verified against real logs from two projects (`cli-integration.nvim` itself and `message-router`), both showing stable sidebar height and zero `showtabline` oscillation after the fix.
