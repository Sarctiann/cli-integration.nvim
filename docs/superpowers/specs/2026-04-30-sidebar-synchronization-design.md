Title: Sidebar Vsplit Synchronization Design
Date: 2026-04-30
Authors: OpenCode (assistant)

Summary
-------
This document describes the design and implementation plan to fix and harden the synchronization between the integration window (sidebar vsplit/fullwidth float) and the editor layout. The change introduces an internal geometry engine, tightens invariants for focus and navigation, and documents required tests.

Goals
-----
- Ensure correct width and positioning of the sidebar vsplit on editor resize.
- Guarantee sidebar vsplit remains inert (no buffers, no focus leaks).
- Ensure fullwidth toggle closes/recreates the vsplit without width drift on restore.
- Preserve existing public API and avoid functional regressions.

Design Overview
---------------
1. Introduce pure helper functions in `lua/cli-integration/window.lua` that compute and apply geometry for sidebar and fullwidth modes.
2. Make `M.update_sidebar_geometry` and `M.resize_sidebars` rely on those helpers as the single source of truth.
3. Harden `create_sidebar_layout` so the vsplit window properties are enforced on creation.
4. Maintain existing autocmds (`WinLeave`, `BufWinEnter`) and keymaps but add defensive checks and reconciliations.

Implementation Steps (high level)
-------------------------------
1. Add helpers: `compute_sidebar_target_geometry`, `compute_fullwidth_geometry`, `apply_float_geometry`, `apply_split_width`.
2. Use helpers in `create_sidebar_layout` to set initial geometry.
3. Refactor `M.update_sidebar_geometry` to call helpers and to properly close/recreate the vsplit during fullwidth toggle.
4. Refactor `M.resize_sidebars` to use width_config as the source of truth for proportional resize.
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
