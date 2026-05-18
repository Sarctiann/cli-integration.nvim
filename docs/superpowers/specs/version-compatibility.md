# Version Compatibility

## Neovim Versions

- **Neovim 0.10+**: Recommended (has winfixbuf, but not used due to error issues)
- **Neovim 0.9+**: Supported (uses BufWinEnter protection instead)
- **Neovim 0.11+**: Uses `jobstart()` instead of `termopen()`

## API Differences

### Terminal Job Start

```lua
local use_jobstart = vim.fn.has("nvim-0.11") == 1

if use_jobstart then
    job_id = vim.fn.jobstart(cmd, { term = true, ... })
else
    job_id = vim.fn.termopen(cmd, { ... })
end
```

### Job ID Retrieval

```lua
-- Neovim >= 0.11
local ok, job_id = pcall(vim.api.nvim_buf_get_var, buf, "terminal_job_id")

-- Fallback for older versions
if not ok then
    job_id = vim.b.terminal_job_id
end
```

## Buffer Lock Strategy

- **Neovim 0.10+**: Has `winfixbuf` but not used (error issues)
- **Neovim 0.9+**: Uses `BufWinEnter` autocmd protection
- Both approaches prevent buffer switching in terminal windows

## Future Considerations

- `winfixbuf` may be used when stable across versions
- `jobstart()` with `term=true` is the modern approach for Neovim 0.11+
