--- Autocommands module
local keymaps = require("cli-integration.keymaps")
local help = require("cli-integration.help")
local config = require("cli-integration.config")

local M = {}

--- Setup autocommands for CLI Integration
--- @param config cli-integration.Config
function M.setup(config)
	local cli_cmd = config.cli_cmd or ""
	if cli_cmd == "" then
		return
	end

	local cli_integration_group = vim.api.nvim_create_augroup("CLI-Integration", { clear = true })
	local cli_integration_opens_group = vim.api.nvim_create_augroup("CLI-Integration-Opens", { clear = true })

	-- Setup keymaps when terminal opens or is entered
	-- Pattern matches any terminal with the CLI command name
	vim.api.nvim_create_autocmd({ "TermOpen", "TermEnter" }, {
		group = cli_integration_group,
		pattern = "term://*" .. cli_cmd .. "*",
		callback = keymaps.setup_terminal_keymaps,
	})

	-- Show help notification when opening the terminal
	if config.show_help_on_open then
		return vim.api.nvim_create_autocmd("TermOpen", {
			group = cli_integration_opens_group,
			pattern = "term://*" .. cli_cmd .. "*",
			callback = help.show_quick_help,
		})
	end
end

return M
