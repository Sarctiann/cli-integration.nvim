--- @module 'cli-integration'

local config = require("cli-integration.config")
local commands = require("cli-integration.commands")
local autocmds = require("cli-integration.autocmds")

local M = {}

--- Setup function for the plugin
--- @param user_config cli-integration.Config
function M.setup(user_config)
	-- Setup configuration
	local configs = config.setup(user_config)

	-- Create user command to open CLI tool
	vim.api.nvim_create_user_command("CLIIntegration", function(opts)
		local args = opts.args

		if args == "open_cwd" or args == "" or not args then
			commands.open_cwd()
		elseif args == "open_root" then
			commands.open_git_root()
		elseif args == "session_list" then
			commands.show_sessions()
		else
			commands.open_custom(args, true)
		end
	end, {
		nargs = "?",
		complete = function()
			return { "open_cwd", "open_root", "session_list" }
		end,
		desc = "Open CLI Integration",
	})

	-- Setup default keymaps
	vim.keymap.set("n", "<leader>aJ", commands.open_cwd, { desc = "Toggle CLI Tool (Current Dir)" })
	vim.keymap.set("n", "<leader>aj", commands.open_git_root, { desc = "Toggle CLI Tool (Project Root)" })
	vim.keymap.set("n", "<leader>al", commands.show_sessions, { desc = "Toggle CLI Tool (Show Sessions)" })

	-- Setup autocommands
	autocmds.setup(configs)
end

return M
