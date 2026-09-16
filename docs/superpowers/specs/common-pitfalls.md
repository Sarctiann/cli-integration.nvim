# Common Pitfalls

1. **Forgetting buffer lock**: Any code that changes window buffer must check if it's a terminal window
2. **Split buffer loading**: Never call `nvim_win_set_buf` on split window
3. **Direct split manipulation**: Always manipulate float, let sync handle split
4. **Missing validation**: Always check `vim.api.nvim_win_is_valid()` and `vim.api.nvim_buf_is_valid()`
5. **Keymap arrays**: All `terminal_keys` values must be arrays, not strings
6. **Integration name spaces**: Remember underscore <-> space normalization for autocompletion
7. **Width calculation**: Remember percentage (1-100) vs absolute (>100) distinction
8. **Cleanup**: Always remove from `M.terminals`, `M.buf_to_name`, `M.sidebars` on close
9. **list_buffer name collision**: If two integrations share the same `name` and both have `list_buffer=true`, the second `nvim_buf_set_name` call silently fails (pcall). Integration names should be unique.
10. **Terminal dimensions at job start**: Always calculate COLUMNS/LINES using `calculate_content_dimensions()` AFTER the window geometry is final. Reading win width/height before `update_sidebar_geometry()` runs will give provisional values (e.g. height=10) and cause TUI apps to render with garbage characters.
11. **Inherited `TERM` from host terminal**: `vim.fn.environ()` propagates the host terminal's `TERM` (e.g. `xterm-ghostty`) into the job. TUI apps then use that terminfo to emit advanced escape sequences that Neovim's `:terminal` does not support, resulting in visible garbage characters (`?1016$p`) and broken mouse paste. Always normalize `TERM` to a safe default (`xterm-256color`) unless the user explicitly overrides it.
12. **tmux OSC 52 "ghost text" from nested terminals**: A CLI tool running inside Neovim's `:terminal`, itself inside tmux, inherits `$TMUX` from the outer shell. Some tools check `$TMUX` and wrap their OSC 52 clipboard writes (e.g. on mouse-copy) in tmux's DCS passthrough envelope, assuming their *immediate* terminal is tmux. But the immediate terminal is actually Neovim's own `:terminal` emulator (libvterm), which doesn't understand that envelope — the raw escape/base64 payload gets rendered as literal text at the cursor. **Fix:** strip `TMUX`/`TMUX_PANE` (and other host-identity vars) from the job's environment in `build_job_env()`, **and** pass `clear_env = true` to `jobstart`/`termopen`. Without `clear_env`, Nvim's `env` option only *extends* the inherited environment (see `:h jobstart-options`) — deleting a key from the table you pass has no effect, since the child still inherits the real `$TMUX` from Nvim's own process.
13. **Double-discounting padding**: `window_width` is the total panel width. The vsplit is created at this exact width. Padding is only discounted when calculating PTY dimensions (`cols = width - padding * 2`). Never discount padding from the vsplit width itself — that causes the TUI to see fewer columns than available.
14. **border_offset is always 0**: `nvim_win_get_width()` for splits returns total width (including foldcolumn), and for floats returns content width (border is outside). There is never a border offset to subtract. The `resize_pty` and `calculate_content_dimensions` functions no longer accept a border parameter.
15. **Fullscreen floats have no padding**: When toggling to fullscreen, the float has no foldcolumn. Always pass `padding = 0` to `resize_pty` for fullscreen and float windows. Using `data.padding` from the sidebar config will incorrectly shrink the PTY.
16. **Always call resize_pty after job creation**: Neovim auto-sizes the PTY based on window geometry, which may differ from our COLUMNS/LINES calculation (due to padding). Calling `resize_pty` after `jobstart`/`termopen` ensures the PTY matches our intended dimensions from the start.
17. **Fullscreen float height formula must be `lines - cmdheight - 3`**: With `border="single"`, `nvim_open_win` positions the top border at `row=0`, content starts at `row+1`, and the bottom border is at `row = height + 1`. The statusline is at `row = lines - cmdheight - 1`. Using `-1` or `-2` causes the bottom border (or content) to overlap the statusline. Only `-3` guarantees `height + 1 < lines - cmdheight`, keeping the statusline visible.

## CRITICAL: Don't fight bufferline over showtabline — cooperate instead

**Do NOT force `vim.o.showtabline` back to `2` from an `OptionSet` autocmd.** It looks like a fix but creates a hidden feedback loop: bufferline's `toggle_bufferline()` runs on nearly every tabline redraw (very frequent while a CLI tool is streaming output) and keeps trying to hide the tabline when it thinks there's only one buffer; your revert happens *nested* inside its own `OptionSet showtabline` callback, so Neovim suppresses firing `OptionSet` for it again (invisible in logs) while still forcing a global chrome resize (all windows lose/gain a row) on every iteration. Confirmed with real logs: **675 `showtabline: 2->0` transitions and 0 `0->2` in 15 seconds** — this was the actual cause of a sidebar window drifting by 1-2 rows unpredictably while a CLI tool was active, not a single clean resize.

**Fix:** flip bufferline's OWN `config.options.always_show_bufferline` flag instead (`adapters/bufline.lua:set_always_show(enabled)`). It re-reads that flag on every call, so once set it naturally stops wanting to hide the tabline — no override, no fight, no storm. Call `set_always_show(true)` wherever the tabline needs to be pinned visible, and `set_always_show(false)` when the last consumer goes away (already folded into `adapters/bufline.lua:restore()`).

**To diagnose a similar drift:** `debug.lua:win_tree_diff(label)` snapshots every window's size/buftype on demand and logs only what changed since the last snapshot — call it before and after reacting to a resize event to see the full sequence of who actually changed size.

## CRITICAL: Fullscreen Window Feature Must Guard BOTH Keymaps and Runtime

`window_features.fullscreen` controls both:
1. **Keymap registration** in `keymaps.lua` — skip fullscreen keymaps entirely if `false`
2. **Runtime toggle** in `terminal.toggle_fullscreen()` — return early if `false`

If only one path is guarded, the user can still toggle via the other. Always check `config.options.window_features.fullscreen == false` in BOTH places.

## CRITICAL: winfixwidth is always true, not tied to dynamic_resize

`winfixwidth` in `layout.lua`'s `apply_sidebar_win_opts()` is unconditionally `true`, regardless of `dynamic_resize`. It only blocks Neovim's *automatic* redistribution when a sibling window opens/closes (Snacks.explorer, a bufferline offset appearing, etc.) — it never blocks our own explicit `nvim_win_set_width` calls, so there is no reason to disable it when `dynamic_resize = true`. A previous version tied it to the feature flag (`winfixwidth = (dynamic_resize == false)`), which let unrelated splits silently resize the sidebar; the reactive resize code then raced to correct it, which was a real source of instability, not a required trade-off.

## Resize event handling

`features/dynamic_resize.lua` reacts to `WinResized`/`VimResized` only — no guessed companion events (a previous version also reacted to `BufReadPost`/`BufDelete` with a 50ms `defer_fn`, in a second near-duplicate resize routine; this raced against bufferline/Snacks' own redraw timing and could apply stale dimensions, and has been removed). `WinResized` fires only after Neovim's layout has actually settled, for any reason a window's size changed.

18. **Redundant SIGWINCH bursts**: `WinResized` can legitimately fire multiple times for the same final window size as sibling windows settle (observed: 3 fires for one file-open, all resolving to the same dimensions). Sending `jobresize` on every fire regardless is wasteful and risky — many TUI frameworks do a full clear+repaint per resize, so a rapid duplicate burst is itself a source of visible rendering corruption. `geometry.lua:resize_pty()` caches the last `(w,h)` sent per `job_id` and skips the call when unchanged (cache cleared in the job's `on_exit`).
