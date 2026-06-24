--- Commands module for opening CLI tool in different modes
local terminal = require("cli-integration.terminal")
local config = require("cli-integration.config")
local debug = require("cli-integration.debug")

local M = {}

--- Get integration by index, name, or cli_cmd
--- @param identifier number|string|nil Integration index (1-based), name string, or cli_cmd string
--- @return Cli-Integration.Integration|nil
--- @return string|nil Error message if integration not found
local function get_integration(identifier)
	local integrations = config.options.integrations or {}
	if not integrations or #integrations == 0 then
		return nil, "No integrations configured. Please configure at least one integration with 'cli_cmd'."
	end

	if not identifier then
		return integrations[1], nil
	end

	if type(identifier) == "number" then
		if identifier < 1 or identifier > #integrations then
			return nil, "Integration index " .. identifier .. " is out of range (1-" .. #integrations .. ")"
		end
		return integrations[identifier], nil
	elseif type(identifier) == "string" then
		local normalized_identifier = identifier:gsub("_", " ")

		for _, integration in ipairs(integrations) do
			if integration.name == normalized_identifier then
				return integration, nil
			end
		end
		for _, integration in ipairs(integrations) do
			if integration.name == identifier then
				return integration, nil
			end
		end
		for _, integration in ipairs(integrations) do
			if integration.cli_cmd == identifier then
				return integration, nil
			end
		end
		return nil, "Integration with name or cli_cmd '" .. identifier .. "' not found"
	end

	return nil, "Invalid identifier type. Expected number or string."
end

--- Open CLI tool in the current file's directory
--- @param integration_identifier number|string|nil Integration index, name, or cli_cmd (defaults to first integration)
--- @param args string|nil Command line arguments for CLI tool
--- @param visual_text string|nil Optional text from visual selection
--- @return nil
function M.open_cwd(integration_identifier, args, visual_text)
	local integration, err = get_integration(integration_identifier)
	if not integration then
		if err then
			vim.notify("cli-integration.nvim: " .. err, vim.log.levels.WARN)
		end
		return
	end

	local working_dir = vim.fn.expand("%:p:h")
	if working_dir == "" then
		working_dir = vim.fn.getcwd()
	end

	debug.log("command_open_cwd", function()
		return { name = integration.name, working_dir = working_dir }
	end)
	terminal.open_terminal(integration, args, integration.keep_open, working_dir, visual_text)
end

--- Open CLI tool in the project root (git root)
--- @param integration_identifier number|string|nil Integration index, name, or cli_cmd (defaults to first integration)
--- @param args string|nil Command line arguments for CLI tool
--- @param visual_text string|nil Optional text from visual selection
--- @return nil
function M.open_git_root(integration_identifier, args, visual_text)
	local integration, err = get_integration(integration_identifier)
	if not integration then
		if err then
			vim.notify("cli-integration.nvim: " .. err, vim.log.levels.WARN)
		end
		return
	end

	local current_file = vim.fn.expand("%:p")
	local current_dir = vim.fn.expand("%:p:h")

	local git_root = vim.fs.find({ ".git" }, {
		path = current_file ~= "" and current_file or current_dir,
		upward = true,
	})[1]

	local working_dir
	if git_root then
		working_dir = vim.fn.fnamemodify(git_root, ":h")
	else
		working_dir = current_dir ~= "" and current_dir or vim.fn.getcwd()
		vim.notify(
			"cli-integration.nvim: Git root not found, using current directory: " .. working_dir,
			vim.log.levels.INFO
		)
	end

	debug.log("command_open_root", function()
		return { name = integration.name, working_dir = working_dir }
	end)
	terminal.open_terminal(integration, args, integration.keep_open, working_dir, visual_text)
end

--- Print debug info about integration terminal dimensions.
--- Useful for diagnosing resize and layout issues.
function M.dbg_print()
	local state = require("cli-integration.window.state")
	local window = require("cli-integration.window")

	vim.print("=== Editor ===")
	vim.print(string.format("columns=%d  lines=%d  showtabline=%s  laststatus=%d  cmdheight=%d",
		vim.o.columns, vim.o.lines, vim.o.showtabline, vim.o.laststatus, vim.o.cmdheight))

	vim.print("=== Sidebars ===")
	if vim.tbl_count(state.sidebars) == 0 then
		vim.print("  (none)")
	end
	for buf, data in pairs(state.sidebars) do
		local sw, fw = data.sidebar_win, data.float_win
		local sw_valid = sw and state.is_valid_win(sw)
		local fw_valid = fw and state.is_valid_win(fw)
		local active_win = sw_valid and sw or (fw_valid and fw or nil)
		local w, h, padding, ft = "?", "?", data.padding or 0, "?"
		if active_win then
			w = vim.api.nvim_win_get_width(active_win)
			h = vim.api.nvim_win_get_height(active_win)
			ft = vim.bo[buf].filetype or "?"
		end
		vim.print(string.format("  buf=%-3d  mode=%-10s  origin=%-8s  sidebar_win=%-4s  float_win=%-4s  w=%-4s  h=%-4s  padding=%d  ft=%s",
			buf, data.mode, data.origin,
			tostring(sw), tostring(fw),
			tostring(w), tostring(h),
			padding, ft))
		if active_win then
			local wfw = vim.wo[active_win].winfixwidth
			local wfh = vim.wo[active_win].winfixheight
			vim.print(string.format("    winfixwidth=%s  winfixheight=%s", tostring(wfw), tostring(wfh)))
		end
	end

	vim.print("=== Terminals ===")
	local term_mod = require("cli-integration.terminal")
	if vim.tbl_count(term_mod.terminals) == 0 then
		vim.print("  (none)")
	end
	for name, td in pairs(term_mod.terminals) do
		local tb = td.term_buf
		local jid = tb and vim.bo[tb].channel or "?"
		local cli_term = td.cli_term or {}
		vim.print(string.format("  %-20s buf=%-3s  job=%-4s  is_fullscreen=%s",
			name, tostring(tb), tostring(jid), tostring(td.is_fullscreen)))
	end
end

return M
