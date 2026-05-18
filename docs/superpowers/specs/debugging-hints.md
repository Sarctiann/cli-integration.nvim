# Debugging Hints

## Buffer Lock Issues

**Check:** BufWinEnter autocmd in window.lua lines 594-665

**Verify:**

- `args.buf != buf` condition fires correctly
- `find_normal_window()` returns valid window
- `M.sidebars` table excludes split_win from normal window search

## Split Navigation Issues

**Check:** WinEnter autocmd in create_proxy_split() lines 309-361

**Verify:**

- `split_win` and `float_win` are valid
- `vim.api.nvim_set_current_win(float_win)` executes
- Dynamic lookup in `M.sidebars` works when float_win is not provided

## Resize Sync Issues

**Check:** M.resize_sidebars() in window.lua lines 924-965

**Verify:**

- VimResized/WinResized autocmd is registered
- `M.sidebars` table integrity
- Split width detection logic distinguishes editor vs manual resize
- `M._last_editor_width` is updated correctly

## Fullwidth Toggle Issues

**Check:** M.update_sidebar_geometry() lines 844-919

**Verify:**

- `is_expanded` state in `M.sidebars[float_win]`
- Split close/recreate logic
- Border changes (none <-> rounded)
- Navigation keymaps are disabled/enabled correctly
- `M._suppress_stopinsert` prevents mode glitches during toggle

## Terminal Job Issues

**Check:** build_job_env() in window.lua lines 95-115

**Verify:**

- `COLUMNS` and `LINES` are set from finalized geometry
- Environment variables are inherited correctly
- `env` overrides are applied
- `unset_env` removals work after merge

## Ready Detection Issues

**Check:** M.attach_text_when_ready() in terminal.lua lines 60-146

**Verify:**

- `cli_ready_flags.search_for` or `cli_cmd` pattern is found
- Polling interval (500ms) and max tries (30) are appropriate
- `start_with_text` function returns string type
