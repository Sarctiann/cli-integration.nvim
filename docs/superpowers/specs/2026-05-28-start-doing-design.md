# start_doing: Migrate from start_with_text to Actions-Based API

## Problem

`start_with_text` returns a string (synchronous, no coroutine support). This is inconsistent with the rest of the API (`format_paths`, `on_ask_submit`) which use an actions table pattern with `send_line`, `send_keys`, `wait`, and coroutine-based execution.

This means:
- `insert_current_path_or_explain_selection` cannot call `integration.format_paths` because the new API expects `(paths, actions)` and returns nil, while the start_with_text flow expects a string.
- Users cannot use `wait()` or leverage coroutine sequencing when inserting initial text.
- The API surface has two patterns (return-value vs. actions) for semantically similar operations.

## Solution

Replace `start_with_text` with `start_doing`: an actions-based callback following the same pattern as `format_paths` and `on_ask_submit`.

### New Type

Add to `config.lua`:

```lua
--- @class Cli-Integration.StartDoingActions
--- @field send_line fun(text: string?) Send text followed by a newline to the terminal via chansend (text defaults to "")
--- @field send_keys fun(keys: string) Send key sequences (Vim key notation like "<CR>", "<Esc>", "<C-c>") via chansend
--- @field wait fun(ms: number) Yield execution for the given milliseconds (coroutine-based, allows terminal to process inputs between actions)
--- @field for_each_path fun(fn: fun(path: string): string|nil) Iterate over all paths, call fn(path), and insert the returned string into the terminal
```

Reuses the exact same method set as `FormatPathsActions`. This is by design — `insert_current_path_or_explain_selection` will call `integration.format_paths({path}, actions)` internally, passing the same actions table.

### Integration Config Change

**Replace:**

```lua
--- @field start_with_text string|(fun(visual_text: string|nil, integration: Cli-Integration.Integration|nil): string)|nil
```

**With:**

```lua
--- @field start_doing (fun(visual_text: string|nil, integration_name: string|nil, actions: Cli-Integration.StartDoingActions): nil)|nil
```

- `visual_text`: text from visual selection, or nil
- `integration_name`: the integration name string (used to look up terminal data)
- `actions`: the actions table

The old `string` variant is removed. Users who want fixed text use `actions.send_line("text")`.

### Hook Changes (`hooks.lua`)

**New signature for `insert_current_path_or_explain_selection`:**

```lua
function M.insert_current_path_or_explain_selection(prefix, suffix)
  -> function(visual_text: string|nil, integration_name: string|nil, actions: Cli-Integration.StartDoingActions) -> nil
```

**Internal logic:**

1. If `visual_text` is provided → `actions.send_line(prefix .. visual_text .. suffix)`
2. If no visual text:
   a. Look up `terminal.terminals[integration_name]` for `current_file`
   b. If found, get `integration` from `terminal.terminals[integration_name].integration`
   c. If `integration.format_paths` exists → call `integration.format_paths({path}, actions)`
   d. Otherwise → `actions.send_line(path)`
3. Fallback: use `expand("%:p")` relative to workspace

### Terminal Changes (`terminal.lua`)

**`attach_text_when_ready`:**
- After ready detection, builds a `StartDoingActions` table (same pattern as `build_format_paths_actions` in `keymaps.lua`)
- Calls `integration.start_doing(visual_text, integration.name, actions)`
- No longer inserts text directly — the callback does it via actions

**`create_new_terminal`** (line ~270):
- Changes `start_with_text` check to `start_doing` check
- Passes `visual_text` through if `start_doing` is set

### Ask Changes (`ask.lua`)

**`open_integration`:**
- Replace `start_with_text` suppression with `start_doing` suppression
- Same pattern: save, set a no-op, restore after creation

### Shared Actions Factory

Extract a shared `build_terminal_actions()` function that all three callers (`format_paths`, `start_doing`, and potentially others) can use. It produces:

```lua
{
  send_line = function(text) ... end,
  send_keys = function(keys) ... end,
  wait = function(ms) ... end,
  for_each_path = function(fn) ... end,
}
```

This lives in `terminal.lua` (since it operates on `term_buf`) and is exported for use by `keymaps.lua` and any other module.

### Future Deprecation

- `start_with_text` is removed entirely, not deprecated. No coexistence period.
- `insert_current_path_or_explain_selection` changes its return type from `string` to `nil` (it now uses actions instead of returning a value).

## Files to Modify

| File | Change |
|------|--------|
| `lua/cli-integration/terminal.lua` | Replace start_with_text flow with start_doing; export `build_terminal_actions` |
| `lua/cli-integration/keymaps.lua` | Use shared `build_terminal_actions` from terminal.lua |
| `lua/cli-integration/hooks.lua` | New signature for `insert_current_path_or_explain_selection` |
| `lua/cli-integration/ask.lua` | Update start_with_text suppression to start_doing |
| `lua/cli-integration/config.lua` | New type annotation, remove `start_with_text` |
| `docs/superpowers/specs/module-config.md` | Document `start_doing` type |
| `docs/superpowers/specs/module-terminal.md` | Update ready detection flow |
| `docs/superpowers/specs/module-hooks.md` | Update `insert_current_path_or_explain_selection` spec |
| `docs/superpowers/specs/module-ask.md` | Update suppression behavior |
| `docs/superpowers/specs/configuration-schema.md` | Update integration schema |
| `docs/superpowers/specs/event-flow.md` | Update terminal creation event flow |
| `README.md` | Update all examples and docs |

## Testing Critical Paths

**Must always work:**
- `start_doing` callback is called after ready detection
- Actions (`send_line`, `send_keys`, `wait`, `for_each_path`) work correctly
- `insert_current_path_or_explain_selection` sends path via actions (not return value)
- `insert_current_path_or_explain_selection` calls `integration.format_paths` if available
- Ask hook suppresses `start_doing` correctly (no double-insertion)
- Coroutine errors in `start_doing` are caught and reported

**Must never happen:**
- `insert_current_path_or_explain_selection` returns a string (old API) — must return nil
- `start_doing` called when ask has suppressed it
- String `start_with_text` value silently ignored during migration
