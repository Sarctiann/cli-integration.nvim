# Event Flow

## Terminal Creation

```
User executes :CLIIntegration open_cwd <integration_name>
  |
  v
commands.open_cwd() -> terminal.open_terminal()
  |
  v
terminal.open_terminal() -> window.create_terminal()
  |
  v
window.create_terminal():
  1. Creates terminal buffer (bufhidden=hide, buflisted=false)
  2. Sets b:cli_integration_name BEFORE termopen/jobstart
  3. Calls create_sidebar_layout() or create_float_window()
  4. Starts terminal job (jobstart/termopen)
  5. Re-applies buffer name AFTER termopen (Neovim overwrites it)
  6. Sets up navigation keymaps (<C-h/j/k/l>)
  7. Sets up BufWinEnter protection autocmd
  8. Sets up auto-insert autocmd
  |
  v
window.create_sidebar_layout():
  1. Creates vsplit on the right side (`botright vsplit`)
  2. Sets terminal buffer in vsplit
  3. Registers in M.sidebars
  4. Sets up WinClosed cleanup autocmd
  5. Sets up VimResized/WinResized sync autocmd
  |
  v
TermOpen event fires -> autocmds.lua triggers keymaps.setup_terminal_keymaps()
  |
  v
keymaps.setup_terminal_keymaps() sets up all terminal-specific keymaps
  |
  v
If show_help_on_open: help.show_quick_help() displays help keys
  |
  v
If start_doing or visual_text: terminal.attach_text_when_ready()
      polls for ready flag (max 30 tries, 500ms intervals)
```

## Buffer Switch Prevention

```
User attempts buffer switch (e.g., :bnext, bufferline click) while in terminal window
  |
  v
BufWinEnter autocmd fires (window.lua)
  |
  v
Detects: args.buf != terminal_buf AND current_win = terminal_win
  |
  v
Case 1: Integration window with different buffer loaded
  1. Restore terminal buffer to terminal window
   2. Find normal window (buftype="", not the sidebar vsplit)
  3. Switch focus to normal window
  4. Load new buffer in normal window
  |
  v
Result: Terminal window unchanged, new buffer in normal window

Case 2: Regular window with terminal buffer loaded
  1. If visible integration float exists, focus it and start insert
  2. Otherwise allow (window already has terminal buffer)
```

## Resize Synchronization

```
User resizes editor or manually resizes split
  |
  v
VimResized or WinResized event fires
  |
  v
M.resize_sidebars() iterates all sidebars
  |
  v
For each sidebar:
  1. Distinguishes editor resize (recalculate from width_config percentage) vs manual resize
  2. Calls M.update_sidebar_geometry(term_buf, is_fullscreen, false)
  |
  v
Result: Sidebar vsplit maintains correct width proportionally
```

## Fullscreen Toggle

```
User presses toggle_fullscreen key (default: <C-f>)
  |
  v
keymaps.lua calls terminal.toggle_fullscreen(term_buf)
  |
  v
terminal.toggle_fullscreen():
  1. Finds term_data from M.terminals[name]
  2. Gets sidebar data from M.sidebars[term_buf]
  3. Checks data.origin:
     - "sidebar" → window.update_sidebar_geometry(term_buf, is_fullscreen, true)
     - "float"   → window.update_float_geometry(term_buf, is_fullscreen, true)
  4. Updates term_data.is_fullscreen
  5. Calls window.set_nav_keymaps_enabled(term_buf, not is_fullscreen)
  |
  v
For sidebar origin (update_sidebar_geometry):
  - If expanding: hides vsplit, opens fullscreen float
  - If restoring: deletes WinClosed guard, closes float, restores vsplit
  |
  v
For float origin (update_float_geometry):
  - If expanding: resizes float to full editor coverage
  - If restoring: restores float to original dimensions
  |
  v
Result: Terminal toggles between sidebar/float and fullscreen modes
```

## Ask Hook Flow

```
User triggers hooks.ask("IntegrationName")
  |
  v
capture_context():
  1. Captures file path, cursor position, visual selection
  2. Stores screen position for input window
  |
  v
open_integration():
  1. Opens or toggles terminal
   2. Suppresses start_doing
  |
  v
Return focus to file window
  |
  v
Restore visual selection if present
  |
  v
show_input() [after 50ms delay]:
  1. Creates outer window (border + icon)
  2. Creates inner window (text input)
  3. Enters insert mode
  |
  v
User types question, presses <CR>
  |
  v
_handle_submit():
  1. Builds AskData with question
  2. Calls on_ask_submit(data, actions)
  3. Auto-focuses terminal unless focus_file() was called
```

## Source

See also: [module-window.md](module-window.md), [module-terminal.md](module-terminal.md), [module-ask.md](module-ask.md)
