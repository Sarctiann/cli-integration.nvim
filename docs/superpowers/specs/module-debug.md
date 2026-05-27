# Debug Module

## Purpose
Zero-overhead debug logging for cli-integration.nvim. When `config.options.debug` is `false` (default), `debug.log()` returns immediately with no overhead. When `true`, structured event logs are appended to `cli-integration-debug.log` in the current working directory.

## Public API

### `debug.log(event, data_fn)`
- **event** (string): Event name (e.g., `"toggle_fullscreen"`, `"create_terminal"`)
- **data_fn** (function): Lazy function returning a table of key-value pairs. Only evaluated when debug is enabled.

## Configuration

```lua
require("cli-integration").setup({
    debug = true,  -- Enable logging
    integrations = { ... }
})
```

## Log Format

```
[YYYY-MM-DD HH:MM:SS] [cli-integration] <event> | key=value key=value ...
```

Example:
```
[2026-05-27 14:32:10] [cli-integration] toggle_fullscreen | buf=5 from_mode=sidebar name=opencode to_mode=fullscreen
```

## Overhead Guarantee

- When `debug = false`: single `if not config.options.debug then return end` per call. No string construction, no I/O, no function evaluation.
- When `debug = true`: lazy data construction, file append, immediate close.

## Instrumented Events

See [2026-05-27-debug-module-design.md](2026-05-27-debug-module-design.md) for the complete list of events and data fields.
