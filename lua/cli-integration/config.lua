--- @class cli-integration.Config
--- @field cli_cmd string|nil # CLI command name to execute (required)
--- @field show_help_on_open boolean|nil # Whether to show help notification when opening the terminal (default: true)
--- @field new_lines_amount number|nil # Number of new lines to insert after command submission (default: 2)
--- @field window_width number|nil # Default width for the terminal window (default: 64)
--- @field terminal_keys table|nil # Key mappings for the CLI terminal window (all values must be arrays)

local M = {}

--- Default configuration
M.defaults = {
	cli_cmd = nil,
	show_help_on_open = true,
	new_lines_amount = 1,
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
function M.setup(config)
	M.options = vim.tbl_deep_extend("force", M.defaults, config or {})
	return M.options
end

return M
