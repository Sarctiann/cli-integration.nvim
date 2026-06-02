# Debugging Hints

## Buffer Lock Issues

**Check:** BufWinEnter autocmd in window.lua lines 594-665

**Verify:**

- `args.buf != buf` condition fires correctly
- `find_normal_window()` returns valid window
- `M.sidebars` table excludes sidebar windows from normal window search

## Sidebar Navigation Issues

**Check:** Vsplit creation in create_sidebar_layout() lines 527-600

**Verify:**

- `sidebar_win` is valid after vsplit creation
- Terminal buffer is correctly set in the vsplit
- `M.sidebars[sidebar_win]` entry is created correctly

## Resize Sync Issues

**Check:** M.resize_sidebars() in window.lua lines ~954-981

**Verify:**

- VimResized/WinResized autocmd is registered
- `M.sidebars` table integrity
- Width detection logic distinguishes editor vs manual resize using `M._last_editor_width`
- `M._last_editor_width` is updated correctly
- Sidebar vsplit width equals `configured_width` (no padding discount)
- `resize_pty` called with correct padding: `data.padding` for sidebar, `0` for fullscreen float

## PTY Size Issues

**Check:** resize_pty() and calculate_content_dimensions() in window.lua lines ~137 and ~226

**Verify:**

- `resize_pty(term_buf, win, padding)` uses 3 parameters (no border parameter)
- For splits: `content_width = w - (padding * 2)` (w includes foldcolumn)
- For floats: `content_width = w` (padding is always 0)
- `resize_pty` is called after jobstart in create_terminal
- Fullscreen floats always pass `padding = 0` to resize_pty

## Fullwidth Toggle Issues

**Check:** M.update_sidebar_geometry() lines 606-696

**Verify:**

- `is_expanded` state in `M.sidebars[sidebar_win]`
- Vsplit close/recreate (float <-> vsplit) logic
- Border changes (none for vsplit <-> rounded for float)
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
- `start_doing` function errors
