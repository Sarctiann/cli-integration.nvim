# CLI-INTEGRATION.NVIM - LLM CONTEXT SPECIFICATION

## PROJECT_IDENTITY

- **Type**: Neovim plugin for CLI tool integration
- **Language**: Lua (Neovim API)
- **Architecture**: Modular, event-driven
- **Core Purpose**: Provide seamless integration between Neovim and CLI tools through managed terminal windows with custom keybindings and workflow automation

## CRITICAL_CONSTRAINTS

1. **Window Buffer Lock**: Terminal windows MUST NEVER change buffers. The terminal window is locked to its terminal buffer only.
2. **Sidebar Vsplit Layout**: Sidebar mode uses a vsplit on the configured side (`window_side`: "left" or "right", default "right") with winfixwidth=true
3. **Fullwidth Float**: Fullwidth mode converts the sidebar to a float covering the full editor width with no border
4. **Terminal Buffer Lock**: The sidebar window MUST NEVER load any buffer content except the terminal buffer
5. **Fullwidth Toggle**: When toggling to fullwidth, the vsplit closes and a float opens; when restoring, the float closes and vsplit reopens

### Canonical Window Terminology

- **Integration Window**: The plugin's terminal window. Modes: `floating`, `sidebar`, `fullwidth` (fullwidth is a variant of the sidebar mode).
- **Sidebar Vsplit**: The vsplit that contains the terminal in sidebar mode, on the configured side (default right). Uses winfixwidth=true and normal panel colors.
- **Runtime Side**: The transient side stored in `M.sidebars[buf].side`. It is independent from `window_side`; the `toggle_window_side` key flips it, fullscreen roundtrips preserve it, and closing the sidebar resets it.

### Window Invariants and Enforcement Rules

- The Sidebar Vsplit is the integration window in sidebar mode: it contains the terminal buffer and uses normal panel colors
- The Sidebar Vsplit uses winfixwidth=true to maintain its configured width
- The sidebar side is created from `window_side`; `toggle_window_side` (default `<C-y>`) only changes the runtime side, never the config
- Fullwidth mode converts the vsplit to a float covering the full editor width with no border
- Toggle restores by closing the float and recreating the vsplit on the preserved runtime side

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
- [module-debug.md](docs/superpowers/specs/module-debug.md) — Debug logging module

### System Specs

- [window-system-architecture.md](docs/superpowers/specs/window-system-architecture.md) — Window modes, invariants, and geometry
- [event-flow.md](docs/superpowers/specs/event-flow.md) — Terminal creation, buffer lock, resize sync, fullwidth toggle, side toggle, ask flow
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
- `2026-11-13-window-side-toggle-design.md` — window_side option and runtime side toggle
