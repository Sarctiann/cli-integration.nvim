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
12. **tmux OSC 52 clipboard leakage**: When `set-clipboard` is `on` or `external` in tmux, copying text with the mouse sends OSC 52 escape sequences that Neovim `:terminal` may pass through to the job as literal text. If you see base64-encoded garbage (e.g. `52;c;...`) in the TUI input when mouse-pasting, add `set -s set-clipboard off` to `.tmux.conf` and restart tmux.
13. **Double-discounting padding**: `window_width` is the total panel width. The vsplit is created at this exact width. Padding is only discounted when calculating PTY dimensions (`cols = width - padding * 2`). Never discount padding from the vsplit width itself — that causes the TUI to see fewer columns than available.
14. **border_offset is always 0**: `nvim_win_get_width()` for splits returns total width (including foldcolumn), and for floats returns content width (border is outside). There is never a border offset to subtract. The `resize_pty` and `calculate_content_dimensions` functions no longer accept a border parameter.
15. **Fullscreen floats have no padding**: When toggling to fullscreen, the float has no foldcolumn. Always pass `padding = 0` to `resize_pty` for fullscreen and float windows. Using `data.padding` from the sidebar config will incorrectly shrink the PTY.
16. **Always call resize_pty after job creation**: Neovim auto-sizes the PTY based on window geometry, which may differ from our COLUMNS/LINES calculation (due to padding). Calling `resize_pty` after `jobstart`/`termopen` ensures the PTY matches our intended dimensions from the start.
17. **Fullscreen float height formula must be `lines - cmdheight - 3`**: With `border="single"`, `nvim_open_win` positions the top border at `row=0`, content starts at `row+1`, and the bottom border is at `row = height + 1`. The statusline is at `row = lines - cmdheight - 1`. Using `-1` or `-2` causes the bottom border (or content) to overlap the statusline. Only `-3` guarantees `height + 1 < lines - cmdheight`, keeping the statusline visible.
