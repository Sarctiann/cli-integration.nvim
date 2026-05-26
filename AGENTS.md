# CLI-INTEGRATION.NVIM - LLM CONTEXT SPECIFICATION

## PROJECT_IDENTITY

- **Type**: Neovim plugin for CLI tool integration
- **Language**: Lua (Neovim API)
- **Architecture**: Modular, event-driven
- **Core Purpose**: Provide seamless integration between Neovim and CLI tools through managed terminal windows with custom keybindings and workflow automation

## CRITICAL_CONSTRAINTS

1. **Window Buffer Lock**: Terminal windows MUST NEVER change buffers. The terminal window is locked to its terminal buffer only.
2. **Sidebar Vsplit Layout**: Sidebar mode uses a vsplit on the right side with winfixwidth=true
3. **Fullwidth Float**: Fullwidth mode converts the sidebar to a float covering the full editor width with no border
4. **Terminal Buffer Lock**: The sidebar window MUST NEVER load any buffer content except the terminal buffer
5. **Fullwidth Toggle**: When toggling to fullwidth, the vsplit closes and a float opens; when restoring, the float closes and vsplit reopens

### Canonical Window Terminology

- **Integration Window**: The plugin's terminal window. Modes: `floating`, `sidebar`, `fullwidth` (fullwidth is a variant of the sidebar mode).
- **Sidebar Vsplit**: The right-side vsplit that contains the terminal in sidebar mode. Uses winfixwidth=true and normal panel colors.

### Window Invariants and Enforcement Rules

- The Sidebar Vsplit is the integration window in sidebar mode: it contains the terminal buffer and uses normal panel colors
- The Sidebar Vsplit uses winfixwidth=true to maintain its configured width
- Fullwidth mode converts the vsplit to a float covering the full editor width with no border
- Toggle restores by closing the float and recreating the vsplit

## SPECIFICATION DIRECTORY

All technical documentation lives in `docs/superpowers/specs/`. Each spec covers one module or system concern.

### Module Specs

- [module-init.md](docs/superpowers/specs/module-init.md) — Plugin entry point and command registration
- [module-config.md](docs/superpowers/specs/module-config.md) — Configuration management and validation
- [module-window.md](docs/superpowers/specs/module-window.md) — Window and terminal lifecycle management
- [module-terminal.md](docs/superpowers/specs/module-terminal.md) — Terminal state management and text insertion
- [module-keymaps.md](docs/superpowers/specs/module-keymaps.md) — Terminal keymap setup and path insertion
- [module-commands.md](docs/superpowers/specs/module-commands.md) — Command execution (open_cwd, open_git_root)
- [module-autocmds.md](docs/superpowers/specs/module-autocmds.md) — Autocommand setup for terminal lifecycle
- [module-buffers.md](docs/superpowers/specs/module-buffers.md) — Buffer path collection and filtering
- [module-help.md](docs/superpowers/specs/module-help.md) — Help text generation and display
- [module-hooks.md](docs/superpowers/specs/module-hooks.md) — Shared hooks and session management
- [module-ask.md](docs/superpowers/specs/module-ask.md) — Ask hook for context-aware questions

### System Specs

- [window-system-architecture.md](docs/superpowers/specs/window-system-architecture.md) — Window modes, invariants, and geometry
- [event-flow.md](docs/superpowers/specs/event-flow.md) — Terminal creation, buffer lock, resize sync, fullwidth toggle, ask flow
- [configuration-schema.md](docs/superpowers/specs/configuration-schema.md) — All configuration types and schemas
- [testing-critical-paths.md](docs/superpowers/specs/testing-critical-paths.md) — Must-always-work and must-never-happen scenarios
- [debugging-hints.md](docs/superpowers/specs/debugging-hints.md) — Debugging guidance by subsystem
- [performance-considerations.md](docs/superpowers/specs/performance-considerations.md) — Lookup and iteration complexity
- [common-pitfalls.md](docs/superpowers/specs/common-pitfalls.md) — Common mistakes to avoid
- [version-compatibility.md](docs/superpowers/specs/version-compatibility.md) — Neovim version support matrix
- [modification-guidelines.md](docs/superpowers/specs/modification-guidelines.md) — Rules for adding features, fixing bugs, and refactoring

### Feature Design Specs (historical)

- `2026-03-30-start-insert-on-click-and-list-buffer-design.md` — start_insert_on_click and list_buffer options
- `2026-04-09-terminal-keys-override-design.md` — terminal_keys merge behavior
- `2026-04-27-list-buffer-start-insert-design.md` — Edge case resolution
- `2026-04-30-sidebar-synchronization-design.md` — Sidebar sync hardening
- `2026-05-12-sidebar-editor-resize-recalculation-design.md` — Width recalculation on resize
- `2026-05-17-ask-hook-design.md` — Ask hook initial design

## FILE_MODIFICATION_HISTORY

- 2026-03-02: Complete rewrite of window.lua to implement robust buffer lock, proxy split navigation, and bidirectional resize synchronization
- 2026-03-02: Created AGENTS.md for LLM context and project documentation
- 2026-03-30: Added start_insert_on_click and list_buffer options (config.lua, terminal.lua, window.lua)
- 2026-03-30: Fixed start_insert_on_click: clicks outside terminal window now correctly move focus to clicked window instead of staying in terminal and entering insert mode
- 2026-04-09: Changed terminal_keys override behavior: per-section (terminal_mode/normal_mode) replacement with key-by-key merge within section
- 2026-04-09: Fixed terminal_keys override timing issue: pass integration directly from autocmd closure to keymaps setup (TermOpen fires before M.buf_to_cli_cmd populated)
- 2026-04-19: Reindexed terminals by integration.name instead of cli_cmd; autocmds use b:cli_integration_name buffer variable instead of pattern matching; buf_to_cli_cmd renamed to buf_to_name; updated hooks.lua, terminal.lua, window.lua, autocmds.lua, keymaps.lua
- 2026-04-24: Fixed TUI garbage characters: job now starts after final geometry is established; COLUMNS/LINES calculated via calculate_content_dimensions() subtracting border_offset (0 or 2), padding\*2, and list_buffer row_offset.
- 2026-04-27: Fixed fullwidth toggle padding loss: M.update_sidebar_geometry() now restores width from width_config instead of reading potentially-adjusted split width (window.lua lines 666-670). This ensures padding is preserved during sidebar restoration after fullwidth mode.
- 2026-04-27: Fixed start_insert_on_click + list_buffer edge-case: added window classification helpers (is_integration_window, is_integration_float_win, is_integration_proxy_split, is_sidebar_split_win) to distinguish integration windows from regular windows; click-insert enters insert only when clicked inside integration window, allowing normal window navigation when integration window is hidden in bufferline; BufWinEnter autocmd now handles separate cases (Case 1: integration window with different buffer loaded -> restore terminal buffer; Case 2: regular window with terminal buffer loaded -> focus integration float if visible, otherwise allow) (window.lua lines 24-78, 401-508)
- 2026-04-30: Hardened sidebar/fullwidth transition and navigation stability: proxy split recreation now anchors on a safe normal layout window (avoids layout competition with sidebars like neo-tree), fullwidth explicitly clears split references (split_win/split_buf), and terminal navigation mappings use `<Cmd>wincmd ...<CR>` form after terminal-normal escape to reduce mode-state glitches during `<C-h>/<C-l>` navigation.
- 2026-05-04: Changed terminal job environment strategy to inherit full Neovim process env by default (preserving NVIM/TERM/TMUX behavior), replaced hardcoded TERM/COLORTERM overrides with `build_job_env()` in window.lua, and added configurable `env`/`unset_env` options at global and per-integration levels (config.lua, terminal.lua, README.md).
- 2026-05-12: Fixed sidebar width recalculation on editor resize: added `M._last_editor_width` state to `window.lua` and refactored `M.resize_sidebars()` to distinguish editor resize (recalculate from `width_config` percentage) from manual split resize (split as source of truth). Also refreshes `_last_editor_width` on `create_sidebar_layout()` to prevent stale-cache misclassification. Fullwidth mode behavior unchanged.
- 2026-05-18: Renamed format_ask_query -> on_ask_submit with actions table API (send/submit/newline/focus_file). Rewrote ask.lua with two-window input architecture (outer border+icon, inner text) eliminating prefix management complexity. Sequential flow: capture -> open terminal -> return to file -> restore selection -> show input with 50ms delay to avoid insert mode race with terminal's scheduled stopinsert.
- 2026-05-18: Restructured documentation: extracted all technical details from AGENTS.md into individual spec files in docs/superpowers/specs/. AGENTS.md is now a minimal reference document.
- 2026-05-26: Strip Ghostty identity vars (GHOSTTY_RESOURCES_DIR, GHOSTTY_SHELL_FEATURES, GHOSTTY_BIN_DIR, TERMINFO) from job env to prevent TUI garbage chars from Ghostty-specific escape sequences (window.lua build_job_env)
- 2026-05-26: Enable bracketed paste mode in terminal jobs via `chansend(job_id, "\x1b[?2004h")` after 500ms delay, so TUI apps (opencode/crossterm) can distinguish pasted text from typed input (window.lua create_terminal)
- 2026-05-26: Revert bracketed paste mode (`chansend` with `\x1b[?2004h]`) — caused additional escape sequences to appear; removed from window.lua, module-window.md, and testing-critical-paths.md
- 2026-05-26: Revert OSC 52 sanitizer (TextChanged autocmd with debounce timer) — did not work and user does not want background processes running; removed from window.lua, module-window.md, common-pitfalls.md, and testing-critical-paths.md
