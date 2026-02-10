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

--- @param config cli-integration.Config
--- @return cli-integration.Config
function M.setup(config)
	local user_config = config or {}
	M.options = vim.tbl_deep_extend("force", M.defaults, user_config)

	-- Apply global defaults to each integration (unless overridden by integration-specific config)
	if M.options.integrations then
		for i, integration in ipairs(M.options.integrations) do
			-- Start with global defaults
			local default_integration = {
				show_help_on_open = M.options.show_help_on_open,
				new_lines_amount = M.options.new_lines_amount,
				window_width = M.options.window_width,
				terminal_keys = M.options.terminal_keys,
			}
			-- Apply integration-specific config (which may override defaults)
			M.options.integrations[i] = vim.tbl_deep_extend("force", default_integration, integration)
		end
	end

	return M.options
end

return M
