# Testing Critical Paths

## Must Always Work

1. **Buffer Lock**: Attempt :bnext, :bprev, :buffer N, bufferline navigation while in terminal -> buffer changes in normal window, terminal unchanged
2. **Split Navigation**: Navigate into split with <C-l> -> focus redirects to float
3. **Split Close**: Attempt :q on split -> float closes instead, split doesn't close alone
4. **Fullscreen Toggle (sidebar)**: Press <C-f> -> vsplit closes, fullscreen float opens; press again -> float closes, vsplit is recreated at the configured width on the preserved runtime side
5. **Fullscreen Toggle (float)**: Press <C-f> -> float resizes to full editor coverage; press again -> float restores original dimensions
6. **Side Toggle (sidebar)**: Press <C-y> -> vsplit moves to the opposite side, same buffer, width, focus and insert mode
7. **Side Survives Fullscreen**: Toggle side, press <C-f> twice -> vsplit comes back on the toggled side
8. **Side Resets On Reopen**: Toggle side, hide the sidebar (<C-q>), reopen -> vsplit uses the configured `window_side` again
9. **Manual Resize**: Resize split with mouse/commands -> float syncs width automatically
10. **Editor Resize**: Resize Neovim window -> float and split maintain proportions
11. **Terminal Toggle**: :CLIIntegration open_cwd -> opens; execute again -> closes; execute again -> reopens
12. **Text Insertion**: Visual select text, :CLIIntegration open_cwd -> text appears in terminal when ready
13. **Path Insertion**: Press <C-p> in terminal -> current file path inserted
14. **All Buffers**: Press <C-p><C-p> -> all open buffer paths inserted
15. **Focus Mode Exit**: Click on bufferline or another window while in terminal insert mode -> focus changes and mode is Normal
16. **Sidebar Left Navigation**: Press <C-h> in sidebar vsplit -> focuses code window to the left (if exists)
17. **Sidebar Return**: Click on sidebar vsplit -> focuses the vsplit directly (no intermediate window)
18. **No TUI garbage on open**: Open opencode or lazygit inside the integration terminal from Ghostty + tmux -> no `?1016$p` or similar garbage characters appear at startup (requires Ghostty identity vars stripped from job env)
19. **Mouse paste works**: Select text with mouse in host tmux, click inside integration terminal -> selected text does NOT appear as bracketed-paste escape sequences (`\e[200~...\e[201~`) in the TUI input
20. **PTY resize on toggle**: Toggle sidebar to fullscreen -> opencode UI should adapt to full width; toggle back -> should adapt to sidebar width. Mouse selection should work in both modes.
21. **Nav keymaps disabled in fullscreen**: Enter fullscreen mode -> <C-h/j/k/l> do nothing (mapped to <Nop>)
22. **Nav keymaps restored on exit fullscreen**: Exit fullscreen mode -> <C-h/j/k/l> navigate between windows again

## Must Never Happen

1. Terminal window shows non-terminal buffer
2. Split window shows any buffer content
3. Vsplit remains visible in fullscreen mode (it should be closed and recreated on restore)
4. Float and split have different widths (except during transition)
5. Closing split closes only split (must close float)
6. Side toggle moves/closes a float or fullscreen window (must be a no-op)
7. Side toggle mutates the configured `window_side`
8. Buffer navigation commands fail with errors
9. Terminal window loses focus to split when navigating
