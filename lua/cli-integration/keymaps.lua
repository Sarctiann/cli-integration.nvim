--- Keymaps module for terminal interactions
local terminal = require("cli-integration.terminal")
local buffers = require("cli-integration.buffers")
local help = require("cli-integration.help")
local config = require("cli-integration.config")
local debug = require("cli-integration.debug")

local M = {}

--- Helper function to set multiple keymaps for the same action
--- @param mode string|string[] The vim mode (e.g., "t", "n", "i", "v")
--- @param keys string[] Array of key combinations
--- @param callback function|string The function to call | or command to execute
--- @param opts table Options for vim.keymap.set
local function set_keymaps(mode, keys, callback, opts)
	for _, key in ipairs(keys) do
		vim.keymap.set(mode, key, callback, opts)
	end
end

--- Setup keymaps for the CLI tool terminal
--- @param known_integration Cli-Integration.Integration|nil Integration passed directly from autocmd (avoids timing issues with TermOpen)
--- @return nil
function M.setup_terminal_keymaps(known_integration)
	local opts = { buffer = 0, silent = true, noremap = true }
	local current_buf = vim.api.nvim_get_current_buf()

	if not vim.api.nvim_buf_is_valid(current_buf) then
		return
	end

	-- Use the integration passed from the autocmd closure (reliable even during TermOpen,
	-- when M.buf_to_name may not yet be populated). Fall back to lookup for other callers.
	local integration = known_integration or terminal.get_integration_for_buf(current_buf)

	local keys = nil
	local new_lines_amount = 2

	if integration and integration.terminal_keys then
		keys = integration.terminal_keys
		new_lines_amount = integration.new_lines_amount or config.options.new_lines_amount or 2
	else
		keys = config.options.terminal_keys
		new_lines_amount = config.options.new_lines_amount or 2
	end

	if not keys or not keys.terminal_mode or not keys.normal_mode then
		return
	end

	local term_data = nil
	local name = terminal.buf_to_name and terminal.buf_to_name[current_buf]
	if name and terminal.terminals[name] then
		term_data = terminal.terminals[name]
	else
		for _, data in pairs(terminal.terminals) do
			if data.term_buf == current_buf then
				term_data = data
				break
			end
		end
	end

	vim.keymap.set("t", "<CR>", "", opts)
	vim.keymap.set("t", "<M-h>", "<Left>", opts)
	vim.keymap.set("t", "<M-j>", "<Down>", opts)
	vim.keymap.set("t", "<M-k>", "<Up>", opts)
	vim.keymap.set("t", "<M-l>", "<Right>", opts)

	if keys.terminal_mode.normal_mode and type(keys.terminal_mode.normal_mode) == "table" then
		set_keymaps("t", keys.terminal_mode.normal_mode, [[<C-\><C-n>]], opts)
	end

	if keys.terminal_mode.insert_file_path and type(keys.terminal_mode.insert_file_path) == "table" then
		set_keymaps("t", keys.terminal_mode.insert_file_path, function()
			debug.log("keymap_insert_file_path", function()
				return { name = integration and integration.name or "unknown", buf = current_buf }
			end)
			if term_data and term_data.current_file then
				local path = term_data.current_file
				local formatted_path = integration
						and integration.format_paths
						and type(integration.format_paths) == "function"
						and integration.format_paths(path)
					or path
				terminal.insert_text(formatted_path .. " ", current_buf)
			end
		end, opts)
	end

	if keys.terminal_mode.insert_all_buffers and type(keys.terminal_mode.insert_all_buffers) == "table" then
		set_keymaps("t", keys.terminal_mode.insert_all_buffers, function()
			debug.log("keymap_insert_all_buffers", function()
				return { name = integration and integration.name or "unknown", buf = current_buf }
			end)
			local working_dir = term_data and term_data.working_dir or nil
			local paths = buffers.get_open_buffers_paths(working_dir)
			for _, path in ipairs(paths) do
				local formatted_path = integration
						and integration.format_paths
						and type(integration.format_paths) == "function"
						and integration.format_paths(path)
					or path
				terminal.insert_text(formatted_path .. "\n", current_buf)
			end
		end, opts)
	end

	if keys.terminal_mode.new_lines and type(keys.terminal_mode.new_lines) == "table" then
		set_keymaps("t", keys.terminal_mode.new_lines, function()
			local new_lines = string.rep("\n", new_lines_amount)
			terminal.insert_text(new_lines, current_buf)
		end, opts)
	end

	if keys.terminal_mode.submit and type(keys.terminal_mode.submit) == "table" then
		set_keymaps({ "n", "t" }, keys.terminal_mode.submit, function()
			debug.log("keymap_submit", function()
				return { name = integration and integration.name or "unknown", buf = current_buf }
			end)
			vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<Enter>", true, false, true), "n")
		end, opts)
	end

	if keys.terminal_mode.enter and type(keys.terminal_mode.enter) == "table" then
		set_keymaps("t", keys.terminal_mode.enter, function()
			vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<Enter>", true, false, true), "n")
		end, opts)
	end

	if keys.terminal_mode.help and type(keys.terminal_mode.help) == "table" then
		set_keymaps("t", keys.terminal_mode.help, function()
			debug.log("keymap_help", function()
				return { name = integration and integration.name or "unknown", buf = current_buf }
			end)
			help.show_help()
		end, opts)
	end

	if keys.terminal_mode.hide and type(keys.terminal_mode.hide) == "table" then
		set_keymaps("t", keys.terminal_mode.hide, function()
			debug.log("keymap_hide", function()
				return { name = integration and integration.name or "unknown", buf = current_buf, mode = "T" }
			end)
			terminal.hide_terminal(current_buf)
		end, opts)
	end

	if keys.terminal_mode.close and type(keys.terminal_mode.close) == "table" then
		set_keymaps("t", keys.terminal_mode.close, function()
			debug.log("keymap_close", function()
				return { name = integration and integration.name or "unknown", buf = current_buf, mode = "T" }
			end)
			terminal.close_terminal(current_buf)
		end, opts)
	end

	if keys.normal_mode.hide and type(keys.normal_mode.hide) == "table" then
		set_keymaps("n", keys.normal_mode.hide, function()
			debug.log("keymap_hide", function()
				return { name = integration and integration.name or "unknown", buf = current_buf, mode = "N" }
			end)
			terminal.hide_terminal(current_buf)
		end, opts)
	end

	if keys.normal_mode.close and type(keys.normal_mode.close) == "table" then
		set_keymaps("n", keys.normal_mode.close, function()
			debug.log("keymap_close", function()
				return { name = integration and integration.name or "unknown", buf = current_buf, mode = "N" }
			end)
			terminal.close_terminal(current_buf)
		end, opts)
	end

	local toggle_opts = { buffer = 0, silent = true }
	if keys.terminal_mode.toggle_fullscreen and type(keys.terminal_mode.toggle_fullscreen) == "table" then
		set_keymaps("i", keys.terminal_mode.toggle_fullscreen, function()
			debug.log("keymap_toggle_fullscreen", function()
				return { name = integration and integration.name or "unknown", buf = current_buf, mode = "I" }
			end)
			terminal.toggle_fullscreen(current_buf)
		end, toggle_opts)
		set_keymaps("t", keys.terminal_mode.toggle_fullscreen, function()
			debug.log("keymap_toggle_fullscreen", function()
				return { name = integration and integration.name or "unknown", buf = current_buf, mode = "T" }
			end)
			terminal.toggle_fullscreen(current_buf)
		end, toggle_opts)
	end
	if keys.normal_mode.toggle_fullscreen and type(keys.normal_mode.toggle_fullscreen) == "table" then
		set_keymaps("n", keys.normal_mode.toggle_fullscreen, function()
			debug.log("keymap_toggle_fullscreen", function()
				return { name = integration and integration.name or "unknown", buf = current_buf, mode = "N" }
			end)
			terminal.toggle_fullscreen(current_buf)
		end, toggle_opts)
		set_keymaps("v", keys.normal_mode.toggle_fullscreen, function()
			debug.log("keymap_toggle_fullscreen", function()
				return { name = integration and integration.name or "unknown", buf = current_buf, mode = "V" }
			end)
			terminal.toggle_fullscreen(current_buf)
		end, toggle_opts)
	end
end

return M
