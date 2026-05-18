Title: Sidebar/Background Split Synchronization Design
Date: 2026-04-30
Authors: OpenCode (assistant)

Summary
-------
This document describes the design and implementation plan to fix and harden the synchronization between the Integration Window (floating/sidebar/fullwidth) and the Background Split (proxy split / vsplit). The change introduces an internal geometry engine, tightens invariants for focus and navigation, and documents required tests.

Goals
-----
- Ensure bidirectional synchronization of width and X position between the sidebar Integration Window and Background Split.
- Guarantee Background Split remains inert (no buffers, no focus).
- Ensure fullwidth toggle hides/recreates the split without width drift on restore.
- Preserve existing public API and avoid functional regressions.

Design Overview
---------------
1. Introduce pure helper functions in `lua/cli-integration/window.lua` that compute and apply geometry for sidebar and fullwidth modes.
2. Make `M.update_sidebar_geometry` and `M.resize_sidebars` rely on those helpers as the single source of truth.
3. Harden `create_proxy_split` so the split buffer/window properties are enforced on creation/recreation.
4. Maintain existing autocmds (`WinEnter`, `QuitPre`, `WinLeave`, `BufWinEnter`) and keymaps but add defensive checks and reconciliations.

Implementation Steps (high level)
-------------------------------
1. Add helpers: `compute_sidebar_target_geometry`, `compute_fullwidth_geometry`, `apply_float_geometry`, `apply_split_width`, `ensure_split_inert`.
2. Use helpers in `create_sidebar_layout` to set initial geometry.
3. Refactor `M.update_sidebar_geometry` to call helpers and to apply synchronized width to both split and float when restoring from fullwidth.
4. Refactor `M.resize_sidebars` to prefer the real `split_win` width as the authoritative observed width when present.
5. Add tests/manual checklist and update AGENTS.md/README.md.

Validation Checklist
--------------------
- Manual test scenarios for resize, toggle, navigation, and buffer locks (see AGENTS.md testing section).

Backward Compatibility
----------------------
No public API changes. All helpers are local to `window.lua` and non-exported.

Docs Updated
------------
- AGENTS.md (terminology and invariants)
- README.md (short glossary)
