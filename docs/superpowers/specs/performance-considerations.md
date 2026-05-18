# Performance Considerations

## Lookup Performance

| Structure       | Lookup                              | Complexity |
| --------------- | ----------------------------------- | ---------- |
| `M.buf_to_name` | terminal buffer -> integration name | O(1)       |
| `M.terminals`   | integration name -> terminal data   | O(1)       |
| `M.sidebars`    | float_win -> sidebar data           | O(1)       |

## Iteration Performance

- **M.sidebars iteration on resize**: O(n) where n = number of open terminals
- **Buffer path collection**: O(n) where n = number of open buffers
- **Window list iteration**: O(n) where n = number of open windows

## Polling Performance

- **Ready detection**: Polls every 500ms, max 30 tries (15 seconds timeout)
- **Help display delay**: 300ms defer to avoid interfering with terminal output
- **Ask input delay**: 50ms to avoid insert mode race with stopinsert

## Memory Considerations

- Terminal buffers use `bufhidden=hide` (not wipe) to preserve history
- Proxy split buffers use `bufhidden=wipe` for cleanup
- `M.sidebars` entries are cleaned up on WinClosed autocmd
- `M.terminals` and `M.buf_to_name` are cleaned up on terminal close
