# Modification Guidelines

## Documentation Sync (mandatory after any feature or change)

After implementing any feature or change, always update both:

1. **Relevant spec files** in `docs/superpowers/specs/` — update module specs, system specs, or create new feature specs
2. **`AGENTS.md`** — only if critical constraints or project identity changes
3. **`README.md`** — user-facing option tables, examples if a new option or behavior was introduced

## Spec Management

### When Creating Features

1. Generate a spec in `docs/superpowers/specs/` first using the `writing-plans` skill
2. Include: design overview, implementation details, test plan, files changed
3. Name format: `YYYY-MM-DD-<feature-name>-design.md`

### When Modifying Code

1. Check existing specs in `docs/superpowers/specs/` for relevant context
2. Update affected module specs with new functions, types, or behavior
3. Update system specs if invariants or flows change

## When Adding Features

1. **Respect buffer lock**: Never bypass BufWinEnter protection in window.lua
2. **Maintain split proxy**: Keep split as navigation-only, no content
3. **Update sync logic**: If changing dimensions, update M.resize_sidebars()
4. **Validate inputs**: Check window/buffer validity before operations
5. **Update cleanup**: Add cleanup logic to WinClosed autocmd if adding state

## When Fixing Bugs

1. **Check autocmds first**: Most issues are autocmd timing or condition problems
2. **Verify state tables**: M.sidebars, M.terminals, M.buf_to_name must stay consistent
3. **Test all modes**: Sidebar, fullwidth, float modes must all work
4. **Test edge cases**: Multiple terminals, rapid toggling, editor resize during operations
5. **Check error handling**: All vim.api calls should use pcall() where appropriate

## When Refactoring

1. **Preserve public API**: M.create_terminal, M.toggle_terminal, M.is_terminal_visible must maintain signatures
2. **Keep module boundaries**: Don't mix window management with terminal management
3. **Maintain event flow**: TermOpen -> keymaps -> help sequence is critical
4. **Document changes**: Update spec files with any architectural changes
5. **Test integration**: Ensure all modules still work together after changes
