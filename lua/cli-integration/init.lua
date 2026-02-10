--- @module 'cli-integration'

local config = require("cli-integration.config")
local commands = require("cli-integration.commands")
local autocmds = require("cli-integration.autocmds")

local M = {}

--- Setup function for the plugin
--- @param user_config cli-integration.Config
--- @return nil
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
		else
			commands.open_custom(args, true)
		end
	end, {
		nargs = "?",
		complete = function()
			return { "open_cwd", "open_root" }
		end,
		desc = "Open CLI Integration",
	})

	-- Setup autocommands
	autocmds.setup(configs)
end

return M
