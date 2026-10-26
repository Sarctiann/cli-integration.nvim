--- @module 'cli-integration.window.features.dynamic_resize'
local M = {}
local state = require("cli-integration.window.state")
local geometry = require("cli-integration.window.geometry")
local layout = require("cli-integration.window.layout")
local debug = require("cli-integration.debug")
local config = require("cli-integration.config")

M._autocmd_setup = false

--- Re-apply the configured geometry of every active integration window.
--- Called from WinResized/VimResized, i.e. only when Neovim reports that a
--- window's size actually changed and the layout has already settled — so
--- there's no need to guess via other events or debounce with a timer.
--- The PTY follows the window on its own (Nvim resizes it), see geometry.lua.
function M.resize_sidebars()
    debug.log("resize_sidebars", function()
        return {
            editor_width = vim.o.columns,
            editor_lines = vim.o.lines,
            cmdheight = vim.o.cmdheight,
            num_sidebars = vim.tbl_count(state.sidebars),
        }
    end)

    for _, data in pairs(state.sidebars) do
        if data.mode == "sidebar" and state.is_valid_win(data.sidebar_win) then
            local w = geometry.calculate_width(data.width_config)
            pcall(vim.api.nvim_win_set_width, data.sidebar_win, w)
        elseif data.float_win and state.is_valid_win(data.float_win) then
            layout.apply_geometry(data.term_buf)
        end
    end
end

--- Setup dynamic resize autocmds
--- @return boolean true if enabled
function M.setup()
    if config.options.window_features and config.options.window_features.dynamic_resize == false then
        return false
    end

    if not M._autocmd_setup then
        local group = vim.api.nvim_create_augroup("CliIntegrationResize", { clear = true })
        vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
            group = group,
            callback = function(args)
                debug.log("resize_event_fired", function()
                    local touched = vim.v.event and vim.v.event.windows or {}
                    local sidebar_dims = {}
                    for buf, data in pairs(state.sidebars) do
                        local win = data.sidebar_win or data.float_win
                        if win and state.is_valid_win(win) then
                            sidebar_dims[buf] = string.format(
                                "win=%d w=%d h=%d in_event=%s",
                                win,
                                vim.api.nvim_win_get_width(win),
                                vim.api.nvim_win_get_height(win),
                                tostring(vim.tbl_contains(touched, win))
                            )
                        end
                    end
                    return {
                        trigger_event = args.event,
                        touched_windows = table.concat(vim.tbl_map(tostring, touched), ","),
                        columns = vim.o.columns,
                        lines = vim.o.lines,
                        cmdheight = vim.o.cmdheight,
                        laststatus = vim.o.laststatus,
                        showtabline = vim.o.showtabline,
                        sidebars_before = vim.inspect(sidebar_dims):gsub("%s+", " "),
                    }
                end)
                -- Full-tree diff BEFORE we react: shows what Neovim itself just
                -- changed (which window, old->new size, buftype/filetype), so we
                -- can tell a genuine external shrink apart from anything we cause.
                debug.win_tree_diff(args.event .. "_before_react")
                M.resize_sidebars()
                -- ...and again AFTER, to catch any further change our own
                -- nvim_win_set_width calls provoke.
                debug.win_tree_diff(args.event .. "_after_react")
            end,
            desc = "Keep integration windows and their PTYs in sync with any layout change",
        })

        M._autocmd_setup = true
    end

    return true
end

return M
