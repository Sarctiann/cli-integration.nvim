# Window Side Configuration and Runtime Toggle

## Overview

Add a `window_side` configuration option (`"left" | "right"`, default `"right"`) at the global and per-integration levels, plus a `toggle_window_side` keymap (default `<C-y>`) that moves an open sidebar to the opposite side at runtime.

The toggle never mutates configuration. It changes only a transient value in the sidebar state, which is discarded when the sidebar is closed.

## Goals

- Let users choose the initial sidebar side through `setup()`.
- Let users flip the side without restarting Neovim or editing config.
- Keep the existing layout, buffer lock, resize, fullscreen, and keymap behavior intact.

## Non-Goals

- No automatic persistence of the toggled side across Neovim restarts.
- No effect on floating windows.
- No new `window_features` flag; the toggle is always available (like `toggle_fullscreen`, but without an on/off feature gate).

## Behavior

### Configuration

- `Cli-Integration.Config.window_side`: `"left" | "right" | nil`, default `"right"`.
- `Cli-Integration.Integration.window_side`: optional override; inherits the global value.
- Invalid values at either level emit a warning and fall back to `"right"` (global) or the global value (integration).
- Ignored when `floating = true`.

### Creation

`create_sidebar_layout(buf, win_opts)` resolves the effective side in this order:

1. `state.sidebars[buf].side` (runtime value)
2. `win_opts.window_side` (configuration, already merged by `config.setup`)
3. `"right"`

It creates the vsplit with `topleft vsplit` for the left side and `botright vsplit` for the right side.

### Runtime toggle

New action `toggle_window_side`, default `{ "<C-y>" }`, available in `terminal_mode` and `normal_mode` and mapped in `i`, `t`, `n`, `v` (mirroring `toggle_fullscreen`).

`terminal.toggle_window_side(term_buf)` delegates to `window.toggle_sidebar_side(term_buf)`:

- No-op unless `data.mode == "sidebar"`; floating and fullscreen windows are ignored.
- Computes the opposite side from the current runtime/config side.
- Closes the current vsplit, then sets `data.side`, then recreates the vsplit.
- Preserves the terminal buffer, configured width, focus, and insert mode.
- Never changes `config.options`.
- Logs `toggle_window_side` and `keymap_toggle_window_side` debug events.

### Persistence rules

| Event | Runtime side |
| --- | --- |
| Toggle side | Flips and stays until the sidebar closes |
| Sidebar to fullscreen to sidebar | Preserved (vsplit is recreated on the same side) |
| Hide (`<C-q>`), toggle terminal, `:q`, process exit | Reset to nil, so the next open uses `window_side` |
| Float/fullscreen toggle attempt | Unchanged (no-op) |

`WinClosed` resets `data.side` only when it is still the entry's current window and `mode ~= "fullscreen"`. The identity check ignores stale close events during the close-and-recreate cycle; ordering the `data.side` assignment after the close keeps the reset from undoing a side switch.

## Implementation

### Files

- `lua/cli-integration/config.lua` — type annotations, default `window_side`, `toggle_window_side` defaults, validation, integration inheritance.
- `lua/cli-integration/window/state.lua` — `SidebarEntry.side`.
- `lua/cli-integration/window/layout.lua` — `resolve_side()`, side-aware vsplit creation, `toggle_sidebar_side()`, `WinClosed` reset rules.
- `lua/cli-integration/window/init.lua` — exports `toggle_sidebar_side`.
- `lua/cli-integration/terminal.lua` — passes `window_side` in `win_opts`, adds `toggle_window_side()`.
- `lua/cli-integration/keymaps.lua` — mappings for the new action.
- `lua/cli-integration/help.lua` — help entries in both sections.

### Documentation

- `README.md` — default config, option tables, keymap tables, geometry details, tips.
- `AGENTS.md` — constraints, terminology, invariants, event-flow description.
- `docs/superpowers/specs/configuration-schema.md`, `module-config.md`, `module-window.md`, `module-terminal.md`, `module-keymaps.md`, `window-system-architecture.md`, `event-flow.md`, `testing-critical-paths.md`.

## Test Plan

Headless Neovim scripts (run with `nvim --headless -u NONE -l <script>`):

1. Defaults: global and inherited integration side are `"right"`.
2. Global/integration overrides resolve correctly; invalid values warn and fall back.
3. Left sidebar starts at column 1; right sidebar ends at the editor edge.
4. Toggle recreates the vsplit on the opposite side, preserving buffer, width, focus.
5. Closing after a toggle resets the runtime side; reopening uses config.
6. Fullscreen roundtrip preserves the toggled side.
7. Toggle is a no-op in float and fullscreen modes.
8. Keymap wiring: `<C-y>` mapped in `t`, `i`, `n`, `v`; help lists "Toggle Sidebar Side".
9. Real terminal buffer (`cat` job) toggle roundtrip.

## Notes

- `<C-'>` was the original proposal but most terminals send a plain `'` for Ctrl+', so it would never fire outside kitty-keyboard-protocol terminals. `<C-y>` is legacy-terminal safe; the only cost is that the CLI loses readline's yank key while the terminal buffer has focus.
- `<C-m>`, `<C-i>`, and `<C-[>` were rejected because they are indistinguishable from Enter, Tab, and Esc.
