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
