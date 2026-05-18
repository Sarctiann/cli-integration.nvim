# Design Spec: Resolve `start_insert_on_click` + `list_buffer` Edge Case

Date: 2026-04-27
Project: `cli-integration.nvim`
Status: Draft for user review

## 1. Problem Statement

When both options are enabled:

- `start_insert_on_click = true`
- `list_buffer = true`

and the CLI terminal buffer appears in bufferline as `[integration.name]`, selecting that buffer can trigger unexpected behavior because terminal-window protections and click-to-insert behavior are applied too broadly.

Current architecture correctly prevents non-terminal buffers from appearing in the integration terminal window and proxy split, but the same guard logic can interfere with regular windows when selecting the listed terminal buffer.

## 2. Expected Behavior (Validated)

### Case A: Integration window is visible

If user clicks `[integration.name]` in bufferline (or selects it via buffer commands):

1. Focus should move to the integration terminal window.
2. Insert mode should be entered as usual for terminal interaction.

### Case B: Integration window is hidden

If user clicks `[integration.name]` in bufferline (or selects it via buffer commands):

1. The terminal buffer should open in the current regular window.
2. Insert mode must **not** be forced.

## 3. Constraints to Preserve

From project architecture (`AGENTS.md`):

1. Terminal window must stay locked to its terminal buffer.
2. Proxy split must remain navigation-only and never load file content.
3. Focus redirection behavior for proxy split must remain stable.
4. `start_insert_on_click` should only be meaningful for actual integration terminal interaction.

## 4. Root Cause Summary

The event handlers in `window.lua` (notably `BufWinEnter`, `WinEnter`, and click mapping path) rely on window/buffer checks that correctly protect integration windows, but they do not fully distinguish between:

- integration-controlled windows (terminal float + proxy split), and
- regular editor windows that may temporarily show the listed terminal buffer.

This causes integration-only behaviors to leak into normal-window scenarios.

## 5. Design Approach

Recommended approach: **Context-aware guards in `window.lua`** (surgical change).

### Why this approach

- Minimal change scope.
- Uses existing state tables (`M.sidebars`) and current event flow.
- Avoids broad refactor while fixing the edge case deterministically.

## 6. Technical Design

### 6.1 Add explicit window-role helpers (`window.lua`)

Introduce local helper predicates to classify context:

- `is_integration_float_win(win, term_buf)`
- `is_integration_proxy_split(win, term_buf)`
- `find_visible_integration_win(term_buf)`
- `is_integration_visible(term_buf)`

These helpers become the source of truth for deciding whether integration-specific behavior should run.

### 6.2 Refine `BufWinEnter` lock behavior

Current lock remains, but branch by window role:

1. **If current window is integration float/proxy**:
   - Keep existing protection: restore terminal buffer in integration window, redirect new buffer to regular window.

2. **If current window is regular window and `args.buf` is this terminal buffer**:
   - If integration window is visible: redirect focus to integration window (avoid duplicate regular rendering of listed terminal).
   - If integration window is hidden: allow terminal buffer in regular window (no forced insert).

### 6.3 Refine secondary `WinEnter` guard

Apply restoration guard only when the entered window is integration float/proxy context.

Do not restore/rewrite buffer when a regular window legitimately displays terminal buffer while integration window is hidden.

### 6.4 Refine `start_insert_on_click` behavior

In normal-mode mouse mapping for terminal buffer:

- Return `"i"` only when click occurs inside an integration-visible terminal window context.
- Otherwise propagate `"<LeftMouse>"` (default behavior), preventing insert-forcing in regular windows.

## 7. Data Flow Impact

No new persistent tables required.

Existing structures remain authoritative:

- `M.sidebars[float_win]` for integration layout state
- terminal buffer id (`buf`) captured per terminal instance

Helpers only interpret current window/state at event time.

## 8. Risk Assessment

Low risk if scoped to condition checks only.

Potential regressions to watch:

1. False negatives in detecting visible integration window (would allow normal-window rendering unexpectedly).
2. Over-aggressive redirection when multiple terminal integrations exist simultaneously.

Mitigation: keep helper checks keyed by exact `term_buf` and valid window handles.

## 9. Validation Plan

Mandatory scenarios:

1. Visible integration + click `[integration.name]` -> focus integration + insert mode.
2. Visible integration + `:buffer` select terminal -> same behavior.
3. Hidden integration + click `[integration.name]` -> open in regular window, no insert.
4. Hidden integration + `:buffer` select terminal -> open in regular window, no insert.
5. Invariants:
   - integration terminal window never shows non-terminal buffer,
   - proxy split never shows content,
   - split->float focus redirection unchanged.

## 10. Files Expected to Change

- `lua/cli-integration/window.lua` (primary)
- `AGENTS.md` (history + behavior notes)
- `README.md` (only if user-facing semantics need clarification)

## 11. Out of Scope

- Large architecture refactor of all window-management logic.
- New config flags.
- Behavior changes outside this edge case.
