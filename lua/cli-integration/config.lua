--- @class cli-integration.TerminalModeKeys
--- @field normal_mode string[] # Keys to enter normal mode
--- @field insert_file_path string[] # Keys to insert current file path
--- @field insert_all_buffers string[] # Keys to insert all open buffer paths
--- @field new_lines string[] # Keys to insert new lines
--- @field submit string[] # Keys to submit command/message
--- @field enter string[] # Keys to send Enter key
--- @field help string[] # Keys to show help
--- @field toggle_width string[] # Keys to toggle window width

--- @class cli-integration.NormalModeKeys
--- @field hide string[] # Keys to hide terminal
--- @field toggle_width string[] # Keys to toggle window width

--- @class cli-integration.TerminalKeys
--- @field terminal_mode cli-integration.TerminalModeKeys # Key mappings for terminal mode
--- @field normal_mode cli-integration.NormalModeKeys # Key mappings for normal mode

--- @class cli-integration.Integration
--- @field cli_cmd string # CLI command name to execute (required)
--- @field show_help_on_open boolean|nil # Whether to show help notification when opening the terminal (default: true)
--- @field new_lines_amount number|nil # Number of new lines to insert after command submission (default: 2)
--- @field window_width number|nil # Default width for the terminal window (default: 64)
--- @field terminal_keys cli-integration.TerminalKeys|nil # Key mappings for the CLI terminal window (all values must be arrays)

--- @class cli-integration.Config
--- @field integrations cli-integration.Integration[] # Array of CLI integrations
--- @field show_help_on_open boolean|nil # Default: whether to show help notification when opening the terminal (applied to all integrations)
--- @field new_lines_amount number|nil # Default: number of new lines to insert after command submission (applied to all integrations)
--- @field window_width number|nil # Default: width for the terminal window (applied to all integrations)
--- @field terminal_keys cli-integration.TerminalKeys|nil # Default: key mappings for the CLI terminal window (applied to all integrations)

local M = {}

--- Default configuration (applied to all integrations unless overridden)
M.defaults = {
	integrations = {},
	show_help_on_open = true,
	new_lines_amount = 2,
	window_width = 64,
	terminal_keys = {
		terminal_mode = {
			normal_mode = { "<M-q>" },
			insert_file_path = { "<C-p>" },
			insert_all_buffers = { "<C-p><C-p>" },
			new_lines = { "<CR>" },
			submit = { "<C-s>" },
			enter = { "<tab>" },
			help = { "<M-?>", "??", "\\\\" },
			toggle_width = { "<C-f>" },
		},
		normal_mode = {
			hide = { "<Esc>" },
			toggle_width = { "<C-f>" },
		},
	},
}

--- Current configuration
M.options = {}

--- Validate that terminal_keys structure is correct (all values must be arrays)
--- @param terminal_keys table|nil
--- @return boolean
local function validate_terminal_keys(terminal_keys)
	if not terminal_keys then
		return true
	end

	local function validate_keys_table(keys_table)
		if type(keys_table) ~= "table" then
			return false
		end
		for _, value in pairs(keys_table) do
			if type(value) == "table" then
				-- Check if it's an array (all keys are numeric)
				local is_array = true
				for k, _ in pairs(value) do
					if type(k) ~= "number" then
						is_array = false
						break
					end
				end
				if not is_array then
					-- It's a nested table, recurse
					if not validate_keys_table(value) then
						return false
					end
				end
			else
				-- Non-table values should not exist in terminal_keys
				return false
			end
		end
		return true
	end

	return validate_keys_table(terminal_keys)
end

--- @param config cli-integration.Config
--- @return cli-integration.Config
function M.setup(config)
	local user_config = config or {}

	-- Validate integrations is a table if provided
	if user_config.integrations ~= nil and type(user_config.integrations) ~= "table" then
		vim.notify(
			"cli-integration.nvim: 'integrations' must be a table/array",
			vim.log.levels.ERROR
		)
		user_config.integrations = {}
	end

	M.options = vim.tbl_deep_extend("force", M.defaults, user_config)

	-- Validate global terminal_keys if provided
	if user_config.terminal_keys and not validate_terminal_keys(M.options.terminal_keys) then
		vim.notify(
			"cli-integration.nvim: 'terminal_keys' values must be arrays",
			vim.log.levels.WARN
		)
		M.options.terminal_keys = M.defaults.terminal_keys
	end

	-- Apply global defaults to each integration (unless overridden by integration-specific config)
	if M.options.integrations then
		for i, integration in ipairs(M.options.integrations) do
			-- Validate integration is a table
			if type(integration) ~= "table" then
				vim.notify(
					"cli-integration.nvim: Integration at index " .. i .. " must be a table",
					vim.log.levels.WARN
				)
				goto continue
			end

			-- Validate cli_cmd is present and not empty
			local cli_cmd = integration.cli_cmd
			if not cli_cmd or type(cli_cmd) ~= "string" or cli_cmd == "" then
				vim.notify(
					"cli-integration.nvim: Integration at index " .. i .. " must have a non-empty 'cli_cmd'",
					vim.log.levels.WARN
				)
				goto continue
			end

			-- Validate terminal_keys if provided
			if integration.terminal_keys and not validate_terminal_keys(integration.terminal_keys) then
				vim.notify(
					"cli-integration.nvim: Integration '" .. cli_cmd .. "' has invalid 'terminal_keys' (values must be arrays)",
					vim.log.levels.WARN
				)
				integration.terminal_keys = nil -- Will use global default
			end

			-- Start with global defaults
			local default_integration = {
				show_help_on_open = M.options.show_help_on_open,
				new_lines_amount = M.options.new_lines_amount,
				window_width = M.options.window_width,
				terminal_keys = M.options.terminal_keys,
			}
			-- Apply integration-specific config (which may override defaults)
			M.options.integrations[i] = vim.tbl_deep_extend("force", default_integration, integration)

			::continue::
		end
	end

	return M.options
end

return M
