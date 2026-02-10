--- Commands module for opening CLI tool in different modes
local terminal = require("cli-integration.terminal")
local config = require("cli-integration.config")

local M = {}

--- Open CLI tool in the current file's directory
function M.open_cwd()
	terminal.working_dir = vim.fn.expand("%:p:h")

	if terminal.working_dir == "" then
		terminal.working_dir = vim.fn.getcwd()
	end
	terminal.open_terminal()
end

--- Open CLI tool in the project root (git root)
function M.open_git_root()
	terminal.current_file = vim.fn.expand("%:p")
	local current_dir = vim.fn.expand("%:p:h")

	terminal.working_dir = vim.fs.find({ ".git" }, {
		path = terminal.current_file,
		upward = true,
	})[1]

	if terminal.working_dir then
		terminal.working_dir = vim.fn.fnamemodify(terminal.working_dir, ":h")
	else
		terminal.working_dir = current_dir ~= "" and current_dir or vim.fn.getcwd()
	end
	terminal.open_terminal()
end

--- Show CLI tool sessions
function M.show_sessions()
	terminal.current_file = vim.fn.expand("%:p")
	local current_dir = vim.fn.expand("%:p:h")

	terminal.working_dir = vim.fs.find({ ".git" }, {
		path = terminal.current_file,
		upward = true,
	})[1]

	if terminal.working_dir then
		terminal.working_dir = vim.fn.fnamemodify(terminal.working_dir, ":h")
	else
		terminal.working_dir = current_dir ~= "" and current_dir or vim.fn.getcwd()
	end
	local custom_cmd = "ls"
	terminal.open_terminal(custom_cmd)
end

--- Open CLI tool with custom arguments
--- @param args string Custom arguments for CLI tool
--- @param keep_open boolean|nil Whether to keep the terminal open
function M.open_custom(args, keep_open)
	terminal.open_terminal(args, keep_open)
end

return M
