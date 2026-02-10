--- Autocommands module
local keymaps = require("cli-integration.keymaps")
local help = require("cli-integration.help")

local M = {}

--- Setup autocommands for CLI Integration
--- @param user_config cli-integration.Config
--- @return nil
function M.setup(user_config)
	local integrations = user_config.integrations or {}
	if not integrations or #integrations == 0 then
		return
	end

	local cli_integration_group = vim.api.nvim_create_augroup("CLI-Integration", { clear = true })
	local cli_integration_opens_group = vim.api.nvim_create_augroup("CLI-Integration-Opens", { clear = true })

	-- Setup autocommands for each integration
	for _, integration in ipairs(integrations) do
		local cli_cmd = integration.cli_cmd or ""
		if cli_cmd == "" then
			goto continue
		end

		-- Setup keymaps when terminal opens or is entered
		-- Pattern matches any terminal with the CLI command name
		vim.api.nvim_create_autocmd({ "TermOpen", "TermEnter" }, {
			group = cli_integration_group,
			pattern = "term://*" .. cli_cmd .. "*",
			callback = keymaps.setup_terminal_keymaps,
		})

		-- Show help notification when opening the terminal
		if integration.show_help_on_open then
			vim.api.nvim_create_autocmd("TermOpen", {
				group = cli_integration_opens_group,
				pattern = "term://*" .. cli_cmd .. "*",
				callback = help.show_quick_help,
			})
		end

		::continue::
	end
end

return M
