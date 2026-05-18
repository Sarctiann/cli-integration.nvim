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

### Canonical Window Terminology

- **Integration Window**: The plugin's terminal window. Modes: `floating`, `sidebar`, `fullwidth` (fullwidth is a variant of the sidebar mode).
- **Background Split**: The right-side vsplit that sits behind the Integration Window in sidebar mode. Also referred to as the `proxy split` or `bg window`. In informal contexts it may be called the "vsplit" when the meaning is clear.

### Window Invariants and Enforcement Rules

- The Background Split is inert: it never contains real buffers, it is not buflisted, and it must never become a normal editable window.
- The Background Split must never take focus. If focus moves to it, code must immediately redirect focus to the Integration Window (or a safe normal window if the Integration Window is not visible).
- Synchronization is bidirectional:
  - If the Background Split width/position changes (manual resize or external layout change), the Integration Window must update width and column (X) to remain visually aligned.
  - If the Integration Window is resized (programmatically or by restoring from fullwidth), the Background Split must be updated to match.
- Fullwidth toggle semantics:
  - sidebar -> fullwidth: the Background Split is closed/hidden and the Integration Window expands to full editor width.
  - fullwidth -> sidebar: the Background Split is recreated and the Integration Window is restored to synchronized geometry.

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
