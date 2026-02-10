--- Keymaps module for terminal interactions
local terminal = require("cli-integration.terminal")
local buffers = require("cli-integration.buffers")
local help = require("cli-integration.help")
local config = require("cli-integration.config")

local M = {}

--- Helper function to set multiple keymaps for the same action
--- @param mode string The vim mode (e.g., "t", "n", "i", "v")
--- @param keys string[] Array of key combinations
--- @param callback function|string The function to call | or command to execute
--- @param opts table Options for vim.keymap.set
local function set_keymaps(mode, keys, callback, opts)
	for _, key in ipairs(keys) do
		vim.keymap.set(mode, key, callback, opts)
	end
end

--- Setup keymaps for the CLI tool terminal
--- @return nil
function M.setup_terminal_keymaps()
	local opts = { buffer = 0, silent = true, noremap = true }
	local current_buf = vim.api.nvim_get_current_buf()

	-- Verify buffer is valid
	if not vim.api.nvim_buf_is_valid(current_buf) then
		return
	end

	-- Get integration for current terminal buffer
	local integration = terminal.get_integration_for_buf(current_buf)

	-- Get terminal keys and new_lines_amount from integration or fallback to global defaults
	local keys = nil
	local new_lines_amount = 2

	if integration and integration.terminal_keys then
		keys = integration.terminal_keys
		new_lines_amount = integration.new_lines_amount or config.options.new_lines_amount or 2
	else
		-- Fallback to global defaults
		keys = config.options.terminal_keys
		new_lines_amount = config.options.new_lines_amount or 2
	end

	if not keys or not keys.terminal_mode or not keys.normal_mode then
		return
	end

	-- Get terminal data for current file and working dir
	-- Use index for faster lookup if available
	local term_data = nil
	local cli_cmd = terminal.buf_to_cli_cmd and terminal.buf_to_cli_cmd[current_buf]
	if cli_cmd and terminal.terminals[cli_cmd] then
		term_data = terminal.terminals[cli_cmd]
	else
		-- Fallback to linear search
		for _, data in pairs(terminal.terminals) do
			if data.term_buf == current_buf then
				term_data = data
				break
			end
		end
	end

	-- NOTE: Prevent default Enter key behavior
	vim.keymap.set("t", "<CR>", "", opts)
	-- NOTE: Map arrow keys
	vim.keymap.set("t", "<M-h>", "<Left>", opts)
	vim.keymap.set("t", "<M-j>", "<Down>", opts)
	vim.keymap.set("t", "<M-k>", "<Up>", opts)
	vim.keymap.set("t", "<M-l>", "<Right>", opts)

	-- Normal mode keymaps
	if keys.terminal_mode.normal_mode and type(keys.terminal_mode.normal_mode) == "table" then
		set_keymaps("t", keys.terminal_mode.normal_mode, [[<C-\><C-n>]], opts)
	end

	-- Insert current file path
	if keys.terminal_mode.insert_file_path and type(keys.terminal_mode.insert_file_path) == "table" then
		set_keymaps("t", keys.terminal_mode.insert_file_path, function()
			if term_data and term_data.current_file then
				terminal.insert_text("@" .. term_data.current_file .. " ", current_buf)
			end
		end, opts)
	end

	-- Insert all open buffer paths
	if keys.terminal_mode.insert_all_buffers and type(keys.terminal_mode.insert_all_buffers) == "table" then
		set_keymaps("t", keys.terminal_mode.insert_all_buffers, function()
			local working_dir = term_data and term_data.working_dir or nil
			local paths = buffers.get_open_buffers_paths(working_dir)
			for _, path in ipairs(paths) do
				terminal.insert_text("@" .. path .. "\n", current_buf)
			end
		end, opts)
	end

	-- New lines
	if keys.terminal_mode.new_lines and type(keys.terminal_mode.new_lines) == "table" then
		set_keymaps("t", keys.terminal_mode.new_lines, function()
			local new_lines = string.rep("\n", new_lines_amount)
			terminal.insert_text(new_lines, current_buf)
		end, opts)
	end

	-- Submit commands
	if keys.terminal_mode.submit and type(keys.terminal_mode.submit) == "table" then
		set_keymaps("t", keys.terminal_mode.submit, function()
			vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<Enter>", true, false, true), "n")
		end, opts)
	end

	-- Enter key
	if keys.terminal_mode.enter and type(keys.terminal_mode.enter) == "table" then
		set_keymaps("t", keys.terminal_mode.enter, function()
			vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<Enter>", true, false, true), "n")
		end, opts)
	end

	-- Help keymaps
	if keys.terminal_mode.help and type(keys.terminal_mode.help) == "table" then
		set_keymaps("t", keys.terminal_mode.help, help.show_help, opts)
	end

	-- Escape to hide (normal mode)
	if keys.normal_mode.hide and type(keys.normal_mode.hide) == "table" then
		set_keymaps("n", keys.normal_mode.hide, function()
			vim.cmd("q")
		end, opts)
	end

	-- Toggle window width for modes i, t, n, v
	local toggle_opts = { buffer = 0, silent = true }
	if keys.terminal_mode.toggle_width and type(keys.terminal_mode.toggle_width) == "table" then
		set_keymaps("i", keys.terminal_mode.toggle_width, function()
			terminal.toggle_width(current_buf)
		end, toggle_opts)
		set_keymaps("t", keys.terminal_mode.toggle_width, function()
			terminal.toggle_width(current_buf)
		end, toggle_opts)
	end
	if keys.normal_mode.toggle_width and type(keys.normal_mode.toggle_width) == "table" then
		set_keymaps("n", keys.normal_mode.toggle_width, function()
			terminal.toggle_width(current_buf)
		end, toggle_opts)
		set_keymaps("v", keys.normal_mode.toggle_width, function()
			terminal.toggle_width(current_buf)
		end, toggle_opts)
	end
end

return M
