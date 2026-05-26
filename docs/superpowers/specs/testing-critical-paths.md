# Testing Critical Paths

## Must Always Work

1. **Buffer Lock**: Attempt :bnext, :bprev, :buffer N, bufferline navigation while in terminal -> buffer changes in normal window, terminal unchanged
2. **Split Navigation**: Navigate into split with <C-l> -> focus redirects to float
3. **Split Close**: Attempt :q on split -> float closes instead, split doesn't close alone
4. **Fullwidth Toggle**: Press <C-f> -> split hides, float expands; press again -> split recreates, float restores
5. **Manual Resize**: Resize split with mouse/commands -> float syncs width automatically
6. **Editor Resize**: Resize Neovim window -> float and split maintain proportions
7. **Terminal Toggle**: :CLIIntegration open_cwd -> opens; execute again -> closes; execute again -> reopens
8. **Text Insertion**: Visual select text, :CLIIntegration open_cwd -> text appears in terminal when ready
9. **Path Insertion**: Press <C-p> in terminal -> current file path inserted
10. **All Buffers**: Press <C-p><C-p> -> all open buffer paths inserted
11. **Focus Mode Exit**: Click on bufferline or another window while in terminal insert mode -> focus changes and mode is Normal
12. **Sidebar Left Navigation**: Press <C-h> in sidebar vsplit -> focuses code window to the left (if exists)
13. **Sidebar Return**: Click on sidebar vsplit -> focuses the vsplit directly (no intermediate window)
14. **No TUI garbage on open**: Open opencode or lazygit inside the integration terminal from Ghostty + tmux -> no `?1016$p` or similar garbage characters appear at startup (requires Ghostty identity vars stripped from job env)
15. **Mouse paste works**: Select text with mouse in host tmux, click inside integration terminal -> selected text does NOT appear as bracketed-paste escape sequences (`\e[200~...\e[201~`) in the TUI input
16. **PTY resize on toggle**: Toggle sidebar to fullwidth -> opencode UI should adapt to full width; toggle back -> should adapt to sidebar width. Mouse selection should work in both modes.

## Must Never Happen

1. Terminal window shows non-terminal buffer
2. Split window shows any buffer content
3. Split remains visible in fullwidth mode
4. Float and split have different widths (except during transition)
5. Closing split closes only split (must close float)
6. Buffer navigation commands fail with errors
7. Terminal window loses focus to split when navigating
