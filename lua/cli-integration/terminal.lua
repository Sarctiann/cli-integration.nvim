--- Terminal management module
local M = {}

-- Terminals storage: indexed by cli_cmd
-- Each entry contains: { cli_term, term_buf, working_dir, current_file, is_expanded, integration }
M.terminals = {}

--- Insert text into the terminal
--- @param text string The text to insert
--- @param term_buf number|nil The terminal buffer (if nil, uses current terminal)
--- @return nil
function M.insert_text(text, term_buf)
	term_buf = term_buf or M.get_current_terminal_buf()
	if term_buf then
		local job_id = vim.b.terminal_job_id or vim.api.nvim_buf_get_var(term_buf, "terminal_job_id")

		if job_id and vim.fn.jobwait({ job_id }, 10)[1] == -1 then
			vim.fn.chansend(job_id, text)
		end
	end
end

--- Get current terminal buffer from active window
--- @return number|nil
function M.get_current_terminal_buf()
	local current_buf = vim.api.nvim_get_current_buf()
	local buftype = vim.api.nvim_get_option_value("buftype", { buf = current_buf })
	if buftype == "terminal" then
		return current_buf
	end
	return nil
end

--- Get integration for a terminal buffer
--- @param term_buf number|nil The terminal buffer
--- @return cli-integration.Integration|nil
function M.get_integration_for_buf(term_buf)
	term_buf = term_buf or M.get_current_terminal_buf()
	if not term_buf then
		return nil
	end

	for _, term_data in pairs(M.terminals) do
		if term_data.term_buf == term_buf then
			return term_data.integration
		end
	end
	return nil
end

--- Attach current file to the terminal when CLI tool is ready
--- @param file_path string The file path to attach
--- @param term_buf number The terminal buffer
--- @param cli_cmd string The CLI command name
--- @param tries number|nil Number of tries so far
--- @return nil
function M.attach_file_when_ready(file_path, term_buf, cli_cmd, tries)
	vim.defer_fn(function()
		tries = tries or 0
		local max_tries = 12

		if tries >= max_tries or not term_buf then
			return
		end

		if not vim.api.nvim_buf_is_valid(term_buf) then
			return
		end

		local buf_lines = vim.api.nvim_buf_get_lines(term_buf, 0, 5, false)
		-- Check if any of the first 5 lines contains the CLI command name
		local found = false
		if cli_cmd and cli_cmd ~= "" then
			for i = 1, #buf_lines do
				if buf_lines[i] and buf_lines[i]:match(cli_cmd) then
					found = true
					break
				end
			end
		end
		if found then
			M.insert_text("@" .. file_path .. "\n\n", term_buf)
			return
		end

		-- Recursively retry after 300ms
		M.attach_file_when_ready(file_path, term_buf, cli_cmd, tries + 1)
	end, 300)
end

--- Show configuration help message
local function show_config_help()
	local help_text = [[
cli-integration.nvim requires configuration.

Minimum configuration:
  require("cli-integration").setup({
    integrations = {
      { cli_cmd = "your-cli-tool" },  -- Required: specify your CLI command name
    },
  })

Example:
  require("cli-integration").setup({
    integrations = {
      { cli_cmd = "cursor-agent" },
    },
  })
]]
	Snacks.notify(help_text, {
		title = "Configuration Required",
		style = "compact",
		history = false,
		timeout = 10000,
	})
end

--- Open or toggle the CLI tool terminal
--- @param integration cli-integration.Integration The integration configuration
--- @param args string|nil Command line arguments for CLI tool
--- @param keep_open boolean|nil Whether to keep the terminal open after execution
--- @param working_dir string|nil Working directory for the terminal
--- @return nil
function M.open_terminal(integration, args, keep_open, working_dir)
	if not integration or not integration.cli_cmd or integration.cli_cmd == "" then
		show_config_help()
		return
	end

	local cli_cmd = integration.cli_cmd
	local term_data = M.terminals[cli_cmd]

	-- Toggle if terminal already exists
	if term_data and term_data.cli_term and term_data.cli_term.toggle then
		term_data.cli_term:toggle()
		return
	end

	-- Create new terminal
	local cmd = args and " " .. args or ""
	local current_file_abs = vim.fn.expand("%:p")

	local base_dir = working_dir or vim.fn.getcwd()
	local current_file = vim.fn.expand("%")
	if base_dir and base_dir ~= "" then
		current_file = vim.fs.relpath(base_dir, current_file_abs) or vim.fn.fnamemodify(current_file_abs, ":.")
	end

	local cli_term = Snacks.terminal(cli_cmd .. cmd, {
		interactive = true,
		cwd = base_dir,
		win = {
			title = " " .. cli_cmd .. " " .. (args and " ( " .. args .. " ) " or ""),
			position = keep_open and "float" or "right",
			min_width = keep_open and nil or integration.window_width,
			border = "rounded",
			on_close = function()
				M.terminals[cli_cmd] = nil
			end,
			resize = true,
		},
		auto_close = not keep_open,
		start_insert = not keep_open,
		auto_insert = not keep_open,
	})

	-- Verify terminal was created successfully
	if not cli_term then
		return
	end

	local term_buf = cli_term.buf

	-- Verify buffer exists
	if not term_buf then
		return
	end

	-- Store terminal data
	M.terminals[cli_cmd] = {
		cli_term = cli_term,
		term_buf = term_buf,
		working_dir = base_dir,
		current_file = current_file,
		is_expanded = false,
		integration = integration,
	}

	-- Attach file if new terminal
	M.attach_file_when_ready(current_file, term_buf, cli_cmd)
end

--- Toggle terminal window width between default and maximum
--- @param term_buf number|nil The terminal buffer (if nil, uses current terminal)
--- @return nil
function M.toggle_width(term_buf)
	term_buf = term_buf or M.get_current_terminal_buf()
	if not term_buf then
		return
	end

	-- Find terminal data
	local term_data = nil
	for _, data in pairs(M.terminals) do
		if data.term_buf == term_buf then
			term_data = data
			break
		end
	end

	if not term_data then
		return
	end

	-- Get the terminal window
	local term_win = nil
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == term_buf then
			term_win = win
			break
		end
	end

	if not term_win or not vim.api.nvim_win_is_valid(term_win) then
		return
	end

	local integration = term_data.integration
	local window_width = integration.window_width
	local columns = vim.o.columns

	-- Calculate maximum width (accounting for borders and margins)
	-- Assuming 2 columns for border (1 on each side)
	local max_width = columns - 2

	if term_data.is_expanded then
		-- Return to default width
		vim.api.nvim_win_set_width(term_win, window_width)
		term_data.is_expanded = false
	else
		-- Expand to maximum width
		vim.api.nvim_win_set_width(term_win, max_width)
		term_data.is_expanded = true
	end
end

return M
