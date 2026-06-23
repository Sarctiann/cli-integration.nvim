--- @module 'cli-integration.window.state'
local M = {}

--- @class Cli-Integration.SidebarEntry
--- @field term_buf number
--- @field mode string  -- "sidebar" | "float" | "fullscreen"
--- @field origin string  -- "sidebar" | "float"
--- @field sidebar_win number|nil
--- @field float_win number|nil
--- @field float_original table|nil
--- @field fullscreen_autocmd_id number|nil
--- @field width_config number
--- @field win_opts table
--- @field padding number
--- @field list_buffer boolean
--- @field _last_pty_width number
--- @field _last_pty_height number
--- @field _last_win_width number|nil
--- @field _last_win_height number|nil
--- @field _pty_resize_pending boolean|nil

--- Store active sidebar configurations
--- Keyed by term_buf (stable across toggles)
--- @type table<number, Cli-Integration.SidebarEntry>
M.sidebars = {}

--- Check if a window is an integration window for a given terminal buffer
--- @param win number Window handle
--- @param term_buf number Terminal buffer
--- @return boolean
function M.is_integration_window(win, term_buf)
    local data = M.sidebars[term_buf]
    return data ~= nil and (data.sidebar_win == win or data.float_win == win)
end

--- @param w number Window handle
--- @return boolean
function M.is_any_integration_win(w)
    for _, d in pairs(M.sidebars) do
        if d.sidebar_win == w or d.float_win == w then
            return true
        end
    end
    return false
end

--- @param win number
--- @return boolean
function M.is_valid_win(win)
    return type(win) == "number" and win > 0 and vim.api.nvim_win_is_valid(win)
end

return M
