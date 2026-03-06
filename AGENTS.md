# CLI-INTEGRATION.NVIM - LLM CONTEXT SPECIFICATION

## PROJECT_IDENTITY
- **Type**: Neovim plugin for CLI tool integration
- **Language**: Lua (Neovim API)
- **Architecture**: Modular, event-driven
- **Core Purpose**: Provide seamless integration between Neovim and CLI tools through managed terminal windows with custom keybindings and workflow automation

## CRITICAL_CONSTRAINTS
1. **Window Buffer Lock**: Terminal windows MUST NEVER change buffers. The terminal window is locked to its terminal buffer only.
2. **Proxy Split Navigation**: Navigation uses a proxy split window that redirects to the floating terminal window.
3. **Split Synchronization**: Split and float windows must maintain bidirectional dimension synchronization.
4. **No Split Buffer Loading**: The proxy split window NEVER loads any buffer content - it's purely for navigation.
5. **Fullwidth Toggle**: When toggling to fullwidth, the split must be hidden; when restoring, it must be recreated.

## MODULE_ARCHITECTURE

### lua/cli-integration/init.lua
**Responsibility**: Plugin entry point and user command registration
**Key Functions**:
- `M.setup(user_config)`: Initializes plugin, creates `:CLIIntegration` command
**Dependencies**: config, commands, autocmds
**Critical Details**:
- Creates user command with autocompletion for actions (open_cwd, open_root) and integration names
- Handles visual selection range for passing text to CLI tools
- Normalizes integration names (underscores ↔ spaces) for autocompletion compatibility
- Validates integrations exist before executing commands

### lua/cli-integration/config.lua
**Responsibility**: Configuration management and validation
**Key Types**:
- `Cli-Integration.Config`: Global configuration
- `Cli-Integration.Integration`: Per-CLI-tool configuration
- `Cli-Integration.TerminalKeys`: Keymap definitions (terminal_mode, normal_mode)
**Key Functions**:
- `M.setup(config)`: Validates and merges user config with defaults
- `validate_terminal_keys(terminal_keys)`: Ensures all keymap values are arrays
**Critical Details**:
- Default window_width: 34 (percentage of editor width)
- Default window_padding: 0
- Default border: "none" for sidebar, "rounded" for float/expanded
- Integration-specific config overrides global defaults
- All terminal_keys values MUST be arrays (validated)
- Minimum cli_cmd length: 2 characters (to avoid false pattern matches)

### lua/cli-integration/window.lua
**Responsibility**: Window and terminal lifecycle management
**Key Data Structures**:
- `M.sidebars`: Table mapping float_win → {split_win, split_buf, terminal_buf, width_config, padding, win_opts, is_expanded}
**Key Functions**:
- `M.create_terminal(cmd, opts)`: Creates terminal buffer, window, job, and protection autocmds
- `M.create_float_window(buf, win_opts)`: Creates centered floating window
- `M.create_sidebar_layout(buf, win_opts)`: Creates proxy split + floating terminal
- `create_proxy_split(width, float_win)`: Creates navigation proxy split (no buffer content)
- `M.update_sidebar_geometry(float_win, is_expanded, should_focus)`: Updates dimensions, handles fullwidth toggle
- `M.resize_sidebars()`: Bidirectional sync on VimResized/WinResized events
- `M.toggle_terminal(terminal)`: Shows/hides terminal window
- `M.is_terminal_visible(terminal)`: Checks if terminal window is valid and visible
**Critical Implementation Details**:
- **Buffer Lock (lines 236-282)**: `BufWinEnter` autocmd prevents any buffer except terminal buffer from loading in terminal window. If detected, restores terminal buffer and redirects new buffer to normal window.
- **Proxy Split (lines 44-110)**:
  - Creates empty scratch buffer (buftype=nofile, modifiable=false)
  - **Focus Redirection**: `WinEnter` autocmd redirects focus to float window using dynamic lookup in `M.sidebars`.
  - **Navigation Skip**: If moving from float to split (e.g., `<C-h>`), `WinEnter` detects `prev_win == float_win` and automatically executes `wincmd h` to skip the split. If no window exists to the left, it returns focus to the float.
  - **Close Redirection**: `QuitPre` autocmd redirects close command to float window using dynamic lookup.
  - Never loads any buffer content
- **Insert Mode Management**:
  - **Auto-enter**: Automatically enters insert mode on `BufEnter`/`WinEnter` (lines 225-234).
  - **Auto-exit**: `WinLeave` autocmd on terminal buffer calls `vim.schedule(function() vim.cmd("stopinsert") end)` to ensure user arrives at destination window in Normal mode (even after mouse clicks on bufferline).
- **Fullwidth Toggle (lines 425-460)**:
  - `is_expanded=true`: Closes split, expands float to full width with rounded border
  - `is_expanded=false`: Recreates split, syncs dimensions from split width
- **Bidirectional Sync (lines 471-497)**: Detects manual split resize by comparing widths, updates float accordingly
- **Navigation Keymaps (lines 218-223)**: `<C-h/j/k/l>` in terminal mode for window navigation
- **Auto-insert Mode (lines 225-234)**: Automatically enters insert mode on BufEnter/WinEnter
- **Width Calculation (lines 30-37)**: Supports percentage (1-100) or absolute (>100) values

### lua/cli-integration/terminal.lua
**Responsibility**: Terminal state management and text insertion
**Key Data Structures**:
- `M.terminals`: Table mapping cli_cmd → {cli_term, term_buf, working_dir, current_file, is_expanded, integration}
- `M.buf_to_cli_cmd`: Reverse index for fast lookup (term_buf → cli_cmd)
**Key Functions**:
- `M.open_terminal(integration, args, keep_open, working_dir, visual_text)`: Creates or toggles terminal
- `M.insert_text(text, term_buf)`: Sends text to terminal via chansend
- `M.attach_text_when_ready(integration, term_buf, tries, visual_text)`: Polls terminal output for ready flag based on `cli_ready_flags`, then inserts text
- `M.toggle_width(term_buf)`: Toggles between default and fullwidth
- `M.hide_terminal(term_buf)`: Hides window, keeps process alive
- `M.close_terminal(term_buf)`: Closes window and kills process
- `M.get_current_terminal_buf()`: Returns current buffer if it's a terminal
- `M.get_integration_for_buf(term_buf)`: Returns integration config for buffer
**Critical Details**:
- Ready detection: Searches range defined by `cli_ready_flags` for `search_for` or `cli_cmd` (max 30 tries, 500ms intervals)
- `start_with_text`: Can be string or function(visual_text) → string
- Visual text priority: visual_text overrides start_with_text string
- Toggle behavior: If terminal exists and valid, toggles visibility; otherwise creates new
- Cleanup: on_close callback removes from M.terminals and M.buf_to_cli_cmd



### lua/cli-integration/keymaps.lua
**Responsibility**: Terminal keymap setup and buffer/file path insertion
**Key Functions**:
- `M.setup_terminal_keymaps()`: Sets up all keymaps for current terminal buffer (called by autocmd on TermOpen/TermEnter)
- `set_keymaps(mode, keys, callback, opts)`: Helper to set multiple keymaps for same action
**Critical Details**:
- Keymaps are buffer-local (buffer=0)
- Gets integration-specific keys or falls back to global config.options.terminal_keys
- **Default Enter Prevention (line 68)**: Maps `<CR>` to empty string to prevent default behavior
- **Arrow Key Mapping (lines 70-73)**: `<M-h/j/k/l>` → arrow keys for terminal navigation
- **File Path Insertion**: Uses `integration.format_paths(path)` if available, otherwise raw path
- **All Buffers Insertion**: Gets paths via buffers.get_open_buffers_paths(working_dir), applies format_paths to each
- **New Lines**: Inserts `new_lines_amount` newlines (default: 2)
- **Submit**: Sends text + newlines
- **Toggle Width**: Calls terminal.toggle_width(current_buf)
- **Hide/Close**: Calls terminal.hide_terminal() or terminal.close_terminal()
- **Help**: Calls help.show_help()

### lua/cli-integration/commands.lua
**Responsibility**: Command execution (open_cwd, open_git_root)
**Key Functions**:
- `get_integration(identifier)`: Resolves integration by index (number), name (string), or cli_cmd (string)
- `M.open_cwd(integration_identifier, args, visual_text)`: Opens terminal in current file's directory
- `M.open_git_root(integration_identifier, args, visual_text)`: Opens terminal in git root (searches upward for .git)
**Critical Details**:
- Identifier resolution order: name (normalized with underscores→spaces) → name (original) → cli_cmd
- Git root search: Uses vim.fs.find({".git"}, {path=current_file, upward=true})
- Fallback: If no git root, uses current directory and notifies user
- Calls terminal.open_terminal(integration, args, keep_open, working_dir, visual_text)

### lua/cli-integration/autocmds.lua
**Responsibility**: Autocommand setup for terminal lifecycle events
**Key Functions**:
- `M.setup(user_config)`: Creates autocommands for each integration
**Critical Details**:
- Creates two augroups: "CLI-Integration" (keymaps), "CLI-Integration-Opens" (help)
- Pattern matching: `term://*<cli_cmd>*` (escapes special chars)
- TermOpen + TermEnter: Calls keymaps.setup_terminal_keymaps() with error handling
- TermOpen (if show_help_on_open): Calls help.show_quick_help() with error handling
- Validates cli_cmd length ≥ 2 characters

### lua/cli-integration/buffers.lua
**Responsibility**: Buffer path collection and filtering
**Key Functions**:
- `M.get_open_buffers_paths(working_dir)`: Returns array of file paths for all listed buffers
**Critical Details**:
- Filters: buflisted=true, buftype="" (normal files only)
- Excludes patterns: "//" (protocol buffers), "neo-tree"
- Path conversion: Absolute → relative to working_dir (if valid directory) or current directory
- Uses vim.fs.relpath() with fallback to vim.fn.fnamemodify(path, ":.")

### lua/cli-integration/help.lua
**Responsibility**: Help text generation and display
**Key Functions**:
- `M.show_help()`: Shows full help notification with all keymaps and CLI commands
- `M.show_quick_help()`: Shows brief help notification with help key combinations
- `generate_help_text()`: Generates formatted help text from config
- `format_keys(keys)`: Joins array of keys with " | "
- `format_help_line(keys, description, key_width)`: Formats line with alignment
- `get_max_key_width(entries)`: Calculates max width for alignment
**Critical Details**:
- Gets integration-specific keys or falls back to global config.options.terminal_keys
- Help sections: "Term Mode", "Norm Mode", "<cli_cmd> commands"
- CLI commands section: Shows generic commands (quit/exit, /, @, !)
- Quick help: Shows only help key combinations on terminal open

## CONFIGURATION_SCHEMA

### Integration Configuration
```lua
{
  cli_cmd = "string",              -- REQUIRED: CLI command name
  name = "string",                 -- REQUIRED: Display name for autocompletion
  show_help_on_open = boolean,     -- Default: true
  new_lines_amount = number,       -- Default: 2
  window_width = number,           -- Default: 34 (percentage 1-100 or absolute >100)
  window_padding = number,         -- Default: 0 (horizontal padding in columns)
  border = "none"|"single"|"double"|"rounded"|"solid"|"shadow", -- Default: "none"
  floating = boolean,              -- Default: false (true = centered float, false = sidebar)
  keep_open = boolean,             -- Default: false (true = keep after exit code 0)
  start_with_text = string|function(visual_text), -- Optional: text to insert when ready
  cli_ready_flags = { search_for = string, from_line = number, lines_amt = number }, -- Optional: config for readiness (default: cli_cmd, 1, 5)
  format_paths = function(path),   -- Optional: format file paths before insertion
  terminal_keys = {                -- Optional: override global keys
    terminal_mode = { ... },
    normal_mode = { ... }
  }
}
```

### Terminal Keys Schema
```lua
terminal_keys = {
  terminal_mode = {
    normal_mode = {"<M-q>"},                    -- Enter normal mode
    insert_file_path = {"<C-p>"},               -- Insert current file path
    insert_all_buffers = {"<C-p><C-p>"},        -- Insert all buffer paths
    new_lines = {"<S-CR>"},                     -- Insert new lines
    submit = {"<C-s>", "<C-CR>"},               -- Submit command
    enter = {"<CR>"},                           -- Send Enter key
    help = {"<M-?>", "??", "\\\\"},             -- Show help
    toggle_width = {"<C-f>"},                   -- Toggle fullwidth
    hide = {"<C-q>"},                           -- Hide window (keep process)
    close = {"<C-S-q>"}                         -- Close window (kill process)
  },
  normal_mode = {
    toggle_width = {"<C-f>"},                   -- Toggle fullwidth
    hide = {"<C-q>"},                           -- Hide window (keep process)
    close = {"<C-S-q>"}                         -- Close window (kill process)
  }
}
```

## WINDOW_SYSTEM_ARCHITECTURE

### Sidebar Mode (default)
```
┌─────────────────────┬──────────────────┐
│                     │  Proxy Split     │  ← Empty buffer, winfixwidth=true
│   Normal Windows    │  (navigation)    │  ← WinEnter → redirects to float
│                     │                  │  ← QuitPre → closes float instead
│                     ├──────────────────┤
│                     │                  │
│                     │  Float Window    │  ← Terminal buffer (locked)
│                     │  (terminal)      │  ← zindex=45, covers split area
│                     │                  │  ← BufWinEnter protection
│                     │                  │
└─────────────────────┴──────────────────┘
```

### Fullwidth Mode (toggle)
```
┌──────────────────────────────────────────┐
│                                          │
│         Float Window (terminal)          │  ← Split hidden
│         Full editor width                │  ← Rounded border
│         zindex=45                        │  ← is_expanded=true
│                                          │
└──────────────────────────────────────────┘
```

### Float Mode (floating=true)
```
        ┌────────────────────┐
        │                    │
        │  Centered Float    │  ← No split
        │  (terminal)        │  ← Rounded border
        │                    │  ← 80% width/height
        └────────────────────┘
```


## EVENT_FLOW

### Terminal Creation
1. User executes `:CLIIntegration open_cwd <integration_name>`
2. commands.open_cwd() → terminal.open_terminal()
3. terminal.open_terminal() → window.create_terminal()
4. window.create_terminal():
   - Creates terminal buffer (bufhidden=hide, buflisted=false)
   - Calls create_sidebar_layout() or create_float_window()
   - Starts terminal job (jobstart/termopen)
   - Sets up navigation keymaps (<C-h/j/k/l>)
   - Sets up BufWinEnter protection autocmd
   - Sets up auto-insert autocmd
5. window.create_sidebar_layout():
   - Creates proxy split (create_proxy_split)
   - Creates float window over split
   - Registers in M.sidebars
   - Sets up WinClosed cleanup autocmd
   - Sets up VimResized/WinResized sync autocmd
6. TermOpen event fires → autocmds.lua triggers keymaps.setup_terminal_keymaps()
7. keymaps.setup_terminal_keymaps() sets up all terminal-specific keymaps
8. If show_help_on_open: help.show_quick_help() displays help keys
9. If start_with_text or visual_text: terminal.attach_text_when_ready() polls for ready flag

### Buffer Switch Prevention
1. User attempts buffer switch (e.g., :bnext, bufferline click) while in terminal window
2. BufWinEnter autocmd fires (window.lua lines 238-282)
3. Detects: args.buf ≠ terminal_buf AND current_win = terminal_win
4. Restores terminal buffer to terminal window
5. Finds normal window (buftype="", not a split proxy)
6. Switches focus to normal window
7. Loads new buffer in normal window
8. Result: Terminal window unchanged, new buffer in normal window

### Resize Synchronization
1. User resizes editor or manually resizes split
2. VimResized or WinResized event fires
3. M.resize_sidebars() iterates all sidebars
4. For each sidebar:
   - Checks if split width ≠ float width (manual resize detected)
   - Calls M.update_sidebar_geometry(float_win, is_expanded, false)
5. M.update_sidebar_geometry():
   - If is_expanded: Updates float to full width
   - If not expanded: Syncs float width from split width, recalculates height from split position/height
6. Result: Float and split maintain synchronized dimensions

### Fullwidth Toggle
1. User presses toggle_width key (default: <C-f>)
2. keymaps.lua calls terminal.toggle_width(term_buf)
3. terminal.toggle_width():
   - Finds terminal window from term_buf
   - Gets current is_expanded state from M.terminals[cli_cmd]
   - Calls window.update_sidebar_geometry(term_win, !is_expanded, true)
4. M.update_sidebar_geometry():
   - If expanding: Closes split, sets float to full width with rounded border
   - If restoring: Recreates split, syncs dimensions, restores configured border
5. Updates is_expanded state in M.terminals[cli_cmd]
6. Result: Terminal toggles between sidebar and fullwidth modes

## TESTING_CRITICAL_PATHS

### Must Always Work
1. **Buffer Lock**: Attempt :bnext, :bprev, :buffer N, bufferline navigation while in terminal → buffer changes in normal window, terminal unchanged
2. **Split Navigation**: Navigate into split with <C-l> → focus redirects to float
3. **Split Close**: Attempt :q on split → float closes instead, split doesn't close alone
4. **Fullwidth Toggle**: Press <C-f> → split hides, float expands; press again → split recreates, float restores
5. **Manual Resize**: Resize split with mouse/commands → float syncs width automatically
6. **Editor Resize**: Resize Neovim window → float and split maintain proportions
7. **Terminal Toggle**: :CLIIntegration open_cwd → opens; execute again → closes; execute again → reopens
8. **Text Insertion**: Visual select text, :CLIIntegration open_cwd → text appears in terminal when ready
9. **Path Insertion**: Press <C-p> in terminal → current file path inserted
10. **All Buffers**: Press <C-p><C-p> → all open buffer paths inserted
11. **Focus Mode Exit**: Click on bufferline or another window while in terminal insert mode → focus changes and mode is Normal
12. **Sidebar Left Navigation**: Press <C-h> in sidebar → skips proxy split and focuses code window (if exists)
13. **Sidebar Return**: Click on proxy split → focus redirects to sidebar via dynamic lookup

### Must Never Happen
1. Terminal window shows non-terminal buffer
2. Split window shows any buffer content
3. Split remains visible in fullwidth mode
4. Float and split have different widths (except during transition)
5. Closing split closes only split (must close float)
6. Buffer navigation commands fail with errors
7. Terminal window loses focus to split when navigating

## DEBUGGING_HINTS

### Buffer Lock Issues
- Check: BufWinEnter autocmd in window.lua lines 238-282
- Verify: args.buf ≠ buf condition
- Verify: find_normal_window() returns valid window
- Check: M.sidebars table for split_win exclusion

### Split Navigation Issues
- Check: WinEnter autocmd in create_proxy_split() lines 71-79
- Verify: split_win and float_win are valid
- Verify: vim.api.nvim_set_current_win(float_win) executes

### Resize Sync Issues
- Check: M.resize_sidebars() in window.lua lines 471-497
- Verify: VimResized/WinResized autocmd is registered
- Check: M.sidebars table integrity
- Verify: split width detection logic

### Fullwidth Toggle Issues
- Check: M.update_sidebar_geometry() lines 401-469
- Verify: is_expanded state in M.sidebars[float_win]
- Check: split close/recreate logic
- Verify: border changes (none ↔ rounded)

## VERSION_COMPATIBILITY
- Neovim 0.10+: Recommended (has winfixbuf, but not used due to error issues)
- Neovim 0.9+: Supported (uses BufWinEnter protection instead)
- Neovim 0.11+: Uses jobstart() instead of termopen()

## PERFORMANCE_CONSIDERATIONS
- M.buf_to_cli_cmd: O(1) lookup for terminal buffer → cli_cmd
- M.terminals: O(1) lookup for cli_cmd → terminal data
- M.sidebars: O(n) iteration on resize (n = number of open terminals)
- Ready detection: Polls every 300ms, max 20 tries (6 seconds timeout)
- Buffer path collection: O(n) where n = number of open buffers

## COMMON_PITFALLS
1. **Forgetting buffer lock**: Any code that changes window buffer must check if it's a terminal window
2. **Split buffer loading**: Never call nvim_win_set_buf on split window
3. **Direct split manipulation**: Always manipulate float, let sync handle split
4. **Missing validation**: Always check vim.api.nvim_win_is_valid() and vim.api.nvim_buf_is_valid()
5. **Keymap arrays**: All terminal_keys values must be arrays, not strings
6. **Integration name spaces**: Remember underscore ↔ space normalization for autocompletion
7. **Width calculation**: Remember percentage (1-100) vs absolute (>100) distinction
8. **Cleanup**: Always remove from M.terminals, M.buf_to_cli_cmd, M.sidebars on close

## MODIFICATION_GUIDELINES

### When Adding Features
1. **Respect buffer lock**: Never bypass BufWinEnter protection in window.lua
2. **Maintain split proxy**: Keep split as navigation-only, no content
3. **Update sync logic**: If changing dimensions, update M.resize_sidebars()
4. **Validate inputs**: Check window/buffer validity before operations
5. **Update cleanup**: Add cleanup logic to WinClosed autocmd if adding state

### When Fixing Bugs
1. **Check autocmds first**: Most issues are autocmd timing or condition problems
2. **Verify state tables**: M.sidebars, M.terminals, M.buf_to_cli_cmd must stay consistent
3. **Test all modes**: Sidebar, fullwidth, float modes must all work
4. **Test edge cases**: Multiple terminals, rapid toggling, editor resize during operations
5. **Check error handling**: All vim.api calls should use pcall() where appropriate

### When Refactoring
1. **Preserve public API**: M.create_terminal, M.toggle_terminal, M.is_terminal_visible must maintain signatures
2. **Keep module boundaries**: Don't mix window management with terminal management
3. **Maintain event flow**: TermOpen → keymaps → help sequence is critical
4. **Document changes**: Update this file with any architectural changes
5. **Test integration**: Ensure all modules still work together after changes

## FILE_MODIFICATION_HISTORY
- 2026-03-02: Complete rewrite of window.lua to implement robust buffer lock, proxy split navigation, and bidirectional resize synchronization
- 2026-03-02: Created AGENTS.md for LLM context and project documentation
