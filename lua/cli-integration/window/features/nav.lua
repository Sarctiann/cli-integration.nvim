--- @module 'cli-integration.window.features.nav'
local M = {}
local config = require("cli-integration.config")

--- Enable or disable window-navigation keymaps for a terminal buffer.
--- @param term_buf number Terminal buffer handle
--- @param enabled boolean
function M.set_nav_keymaps_enabled(term_buf, enabled)
	if not vim.api.nvim_buf_is_valid(term_buf) then
		return
	end
	local modes = { "t", "n" }
	local opts = { buffer = term_buf, noremap = true, silent = true }

	if enabled then
		for _, mode in ipairs(modes) do
			vim.keymap.set(mode, "<C-h>", [[<C-\><C-n><Cmd>wincmd h<CR>]], opts)
			vim.keymap.set(mode, "<C-j>", [[<C-\><C-n><Cmd>wincmd j<CR>]], opts)
			vim.keymap.set(mode, "<C-k>", [[<C-\><C-n><Cmd>wincmd k<CR>]], opts)
			vim.keymap.set(mode, "<C-l>", [[<C-\><C-n><Cmd>wincmd l<CR>]], opts)
		end
	else
		for _, mode in ipairs(modes) do
			vim.keymap.set(mode, "<C-h>", "<Nop>", opts)
			vim.keymap.set(mode, "<C-j>", "<Nop>", opts)
			vim.keymap.set(mode, "<C-k>", "<Nop>", opts)
			vim.keymap.set(mode, "<C-l>", "<Nop>", opts)
		end
	end
end

--- Setup nav feature
--- @param term_buf number Terminal buffer
--- @return boolean true if enabled
function M.setup(term_buf)
	if config.options.window_features and config.options.window_features.nav_keymaps == false then
		M.set_nav_keymaps_enabled(term_buf, false)
		return false
	end
	M.set_nav_keymaps_enabled(term_buf, true)
	return true
end

return M
