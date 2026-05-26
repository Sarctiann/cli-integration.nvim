# Terminal Keys Override Design

## Problem Statement

Currently, when an integration defines `terminal_keys`, `vim.tbl_deep_extend` merges them with global defaults. This means that if a user configures:

- Global: `insert_file_path = {"<C-p>"}`
- Integration: `insert_file_path = {"<C-o>"}`

The integration should NOT respond to `<C-p>` (it should only respond to `<C-o>`), but currently both keys work because of deep merge.

## Expected Behavior

| Level           | `terminal_keys` defined | Result                                                                                                 |
| --------------- | ----------------------- | ------------------------------------------------------------------------------------------------------ |
| Plugin (global) | Yes                     | Used as base defaults                                                                                  |
| Integration     | No                      | Inherits all from plugin                                                                               |
| Integration     | Yes (partial)           | Replaces entire sub-section (terminal_mode or normal_mode), then merges key-by-key within that section |

## Implementation

### config.lua

Change the merge strategy in `M.setup()`:

**Current (line 219):**

```lua
M.options.integrations[i] = vim.tbl_deep_extend("force", default_integration, integration)
```

**New approach:**

1. Separate handling for `terminal_keys` - don't use `tbl_deep_extend`
2. For each integration, check if `terminal_keys` is defined
3. If yes: replace entire `terminal_mode` and/or `normal_mode` sub-sections
4. Then merge key-by-key within each sub-section

Pseudo-code:

```lua
-- Get plugin defaults
local plugin_tkeys = M.options.terminal_keys

-- Get integration overrides (if any)
local int_tkeys = integration.terminal_keys

-- Build final terminal_keys
local final_tkeys = {}

-- terminal_mode: if integration defines it, replace else inherit
if int_tkeys and int_tkeys.terminal_mode then
  final_tkeys.terminal_mode = vim.tbl_extend("force", plugin_tkeys.terminal_mode, int_tkeys.terminal_mode)
else
  final_tkeys.terminal_mode = plugin_tkeys.terminal_mode
end

-- normal_mode: same logic
if int_tkeys and int_tkeys.normal_mode then
  final_tkeys.normal_mode = vim.tbl_extend("force", plugin_tkeys.normal_mode, int_tkeys.normal_mode)
else
  final_tkeys.normal_mode = plugin_tkeys.normal_mode
end
```

### keymaps.lua

No changes needed - it already correctly reads from `integration.terminal_keys`.

## Test Cases

1. **Plugin defines all keys, integration defines none** → All keys work as plugin defines
2. **Plugin defines all keys, integration overrides one key in terminal_mode** → Overridden key uses integration value, rest use plugin values
3. **Plugin defines all keys, integration overrides entire terminal_mode** → All terminal_mode keys use integration values, normal_mode uses plugin
4. **Plugin defines all keys, integration defines terminal_keys with ONLY terminal_mode** → terminal_mode uses integration, normal_mode inherits from plugin (because integration didn't define normal_mode)

## Files Modified

- `lua/cli-integration/config.lua` - Lines ~201-219 (terminal_keys merge logic)
