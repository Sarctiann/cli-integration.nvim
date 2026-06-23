--- Terminal management module
local M = {}
local window = require("cli-integration.window")
local debug = require("cli-integration.debug")
local config = require("cli-integration.config")

M.terminals = {}
M.buf_to_name = {}

--- Insert text into the terminal
--- @param text string The text to insert
--- @param term_buf number|nil The terminal buffer (if nil, uses current terminal)
--- @return nil
function M.insert_text(text, term_buf)
	term_buf = term_buf or M.get_current_terminal_buf()
	if term_buf then
		if config.options.debug then
			local name = M.buf_to_name[term_buf] or "unknown"
			debug.log("insert_text", function()
				return { name = name, text_length = #text }
			end)
		end
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
--- @return Cli-Integration.Integration|nil
function M.get_integration_for_buf(term_buf)
	term_buf = term_buf or M.get_current_terminal_buf()
	if not term_buf then
		return nil
	end

	local name = M.buf_to_name[term_buf]
	if name and M.terminals[name] then
		return M.terminals[name].integration
	end

	return nil
end

--- Attach text to the terminal when CLI tool is ready
--- @param integration Cli-Integration.Integration The integration configuration
--- @param term_buf number The terminal buffer
--- @param tries number|nil Number of tries so far
--- @param visual_text string|nil Optional text from visual selection (passed to start_doing function if set)
--- @return nil
function M.attach_text_when_ready(integration, term_buf, tries, visual_text)
	vim.defer_fn(function()
		tries = tries or 0
		local max_tries = 30

		if tries >= max_tries or not term_buf then
			return
		end

		if not vim.api.nvim_buf_is_valid(term_buf) then
			return
		end

		local ready_flags = integration.cli_ready_flags or {}
		local search_flag = (ready_flags.search_for and ready_flags.search_for ~= "") and ready_flags.search_for
			or integration.cli_cmd
			or ""
		local from_line = ready_flags.from_line or 1
		local lines_amt = ready_flags.lines_amt or 5

		local start_line = math.max(0, from_line - 1)
		local end_line = start_line + lines_amt
		local buf_lines = vim.api.nvim_buf_get_lines(term_buf, start_line, end_line, false)

		local found = false
		if search_flag and search_flag ~= "" then
			for i = 1, #buf_lines do
				if buf_lines[i] and buf_lines[i]:match(search_flag) then
					found = true
					break
				end
			end
		end

		if found then
			debug.log("attach_text_ready", function()
				return { name = integration.name or integration.cli_cmd, term_buf = term_buf, tries = tries }
			end)

			local start_doing = integration.start_doing
			if start_doing and type(start_doing) == "function" then
				local co = nil
				local function resume_co()
					if co and coroutine.status(co) == "suspended" then
						local ok, err = coroutine.resume(co)
						if not ok then
							vim.notify(
								"cli-integration.nvim: start_doing error: " .. tostring(err),
								vim.log.levels.ERROR
							)
						end
					end
				end

				local actions = {
					send_line = function(text)
						M.insert_text((text or "") .. "\n", term_buf)
					end,
					send_keys = function(keys)
						local converted = vim.api.nvim_replace_termcodes(keys, true, true, true)
						M.insert_text(converted, term_buf)
					end,
					wait = function(ms)
						vim.defer_fn(resume_co, ms)
						coroutine.yield()
					end,
				}

				co = coroutine.create(function()
					local ok, err = pcall(start_doing, visual_text, actions)
					if not ok then
						vim.notify("cli-integration.nvim: start_doing error: " .. tostring(err), vim.log.levels.ERROR)
					end
				end)
				coroutine.resume(co)
			elseif visual_text then
				M.insert_text(visual_text, term_buf)
			end
			return
		end

		M.attach_text_when_ready(integration, term_buf, tries + 1, visual_text)
	end, 500)
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
	vim.notify(help_text, vim.log.levels.WARN)
end

--- Create a new terminal instance (assumes toggle check already passed)
--- @param integration Cli-Integration.Integration The integration configuration
--- @param args string|nil Command line arguments for CLI tool
--- @param keep_open boolean|nil Whether to keep the terminal open after execution
--- @param working_dir string|nil Working directory for the terminal
--- @param visual_text string|nil Optional text from visual selection (passed to start_doing function if set)
--- @return nil
local function create_new_terminal(integration, args, keep_open, working_dir, visual_text)
	local cli_cmd = integration.cli_cmd
	local name = integration.name
	local cmd = args and " " .. args or ""
	local current_file_abs = vim.fn.expand("%:p")
	local base_dir = working_dir or vim.fn.getcwd()
	local current_file = vim.fn.expand("%")
	if base_dir and base_dir ~= "" and current_file_abs ~= "" then
		current_file = vim.fs.relpath(base_dir, current_file_abs) or vim.fn.fnamemodify(current_file_abs, ":.")
	end
	debug.log("open_terminal", function()
		return { name = name, cli_cmd = cli_cmd, working_dir = base_dir }
	end)

	-- Run pre-launch hook if configured
	debug.log("hook_on_open", function()
		return { name = name, working_dir = base_dir }
	end)
	if integration.on_open then
		local ok, err = pcall(integration.on_open, integration, base_dir)
		if not ok then
			vim.notify(
				"cli-integration.nvim: on_open hook failed for '" .. name .. "': " .. tostring(err),
				vim.log.levels.WARN
			)
		end
	end

	local cli_term = window.create_terminal(cli_cmd .. cmd, {
		interactive = true,
		cwd = base_dir,
		env = integration.env,
		unset_env = integration.unset_env,
		win = {
			title = " " .. name .. " ",
			position = integration.floating and "float" or "right",
			min_width = integration.floating and nil or integration.window_width,
			padding = integration.window_padding or 0,
			border = integration.border,
			start_insert_on_click = integration.start_insert_on_click,
			list_buffer = integration.list_buffer,
			buffer_name = "[" .. name .. "]",
			integration_name = name,
			on_close = function()
				local stored_data = M.terminals[name]
				debug.log("hook_on_close", function()
					return {
						name = name,
						working_dir = M.terminals[name] and M.terminals[name].working_dir or "unknown",
					}
				end)
				M.terminals[name] = nil
				if stored_data and stored_data.term_buf then
					M.buf_to_name[stored_data.term_buf] = nil
				end
				if integration.on_close then
					local ok, err = pcall(integration.on_close, integration, base_dir)
					if not ok then
						vim.notify(
							"cli-integration.nvim: on_close hook failed for '" .. name .. "': " .. tostring(err),
							vim.log.levels.WARN
						)
					end
				end
			end,
			resize = true,
		},
		auto_close = not keep_open,
	})

	if not cli_term then
		vim.notify("cli-integration.nvim: Failed to create terminal for " .. name, vim.log.levels.ERROR)
		return
	end

	local term_buf = cli_term.buf
	if not term_buf then
		vim.notify("cli-integration.nvim: Terminal buffer not available for " .. name, vim.log.levels.ERROR)
		return
	end

	M.terminals[name] = {
		cli_term = cli_term,
		term_buf = term_buf,
		working_dir = base_dir,
		current_file = current_file,
		is_fullscreen = false,
		integration = integration,
	}

	M.buf_to_name[term_buf] = name

	local start_doing = integration.start_doing
	if visual_text or (start_doing ~= nil and type(start_doing) == "function") then
		M.attach_text_when_ready(integration, term_buf, nil, visual_text)
	end
end

--- Open or toggle the CLI tool terminal
--- @param integration Cli-Integration.Integration The integration configuration
--- @param args string|nil Command line arguments for CLI tool
--- @param keep_open boolean|nil Whether to keep the terminal open after execution
--- @param working_dir string|nil Working directory for the terminal
--- @param visual_text string|nil Optional text from visual selection (passed to start_doing function if set)
--- @return nil
function M.open_terminal(integration, args, keep_open, working_dir, visual_text)
	if not integration or not integration.cli_cmd or integration.cli_cmd == "" then
		show_config_help()
		return
	end

	local name = integration.name
	local term_data = M.terminals[name]

	if term_data and term_data.cli_term and term_data.cli_term.toggle then
		if term_data.term_buf and vim.api.nvim_buf_is_valid(term_data.term_buf) then
			debug.log("toggle_terminal", function()
				return { name = name, term_buf = term_data.term_buf }
			end)
			term_data.cli_term:toggle()
			return
		else
			M.terminals[name] = nil
			if term_data.term_buf then
				M.buf_to_name[term_data.term_buf] = nil
			end
		end
	end

	local open_delay = integration.open_delay or 0
	if open_delay > 0 then
		vim.defer_fn(function()
			create_new_terminal(integration, args, keep_open, working_dir, visual_text)
		end, open_delay)
		return
	end

	create_new_terminal(integration, args, keep_open, working_dir, visual_text)
end

--- Toggle terminal window fullscreen between default and maximum
--- @param term_buf number|nil The terminal buffer (if nil, uses current terminal)
--- @return nil
function M.toggle_fullscreen(term_buf)
	if config.options.window_features and config.options.window_features.fullscreen == false then
		return
	end

	term_buf = term_buf or M.get_current_terminal_buf()
	if not term_buf then
		return
	end

	local name = M.buf_to_name[term_buf]
	local term_data = name and M.terminals[name]

	if not term_data then
		return
	end

	local integration = term_data.integration
	if not integration then
		return
	end

	local is_fullscreen = not (term_data.is_fullscreen or false)
	debug.log("toggle_fullscreen", function()
		return {
			name = name,
			buf = term_buf,
			from_mode = term_data.is_fullscreen and "fullscreen" or "sidebar",
			to_mode = is_fullscreen and "fullscreen" or "sidebar",
		}
	end)
	local data = window.sidebars[term_buf]

	if data and data.origin == "sidebar" then
		window.update_sidebar_geometry(term_buf, is_fullscreen, true)
	elseif data and data.origin == "float" then
		window.update_float_geometry(term_buf, is_fullscreen, true)
	else
		-- Fallback: no sidebar data, resize existing window directly
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

		local editor_width = vim.o.columns
		local width_config = integration.window_width or 34
		local default_width
		if width_config <= 100 then
			local percentage = width_config <= 1 and width_config or (width_config / 100)
			default_width = math.floor(editor_width * percentage)
		else
			default_width = width_config
		end

		if is_fullscreen then
			vim.api.nvim_win_set_width(term_win, editor_width - 2)
		else
			vim.api.nvim_win_set_width(term_win, default_width)
		end
		-- Notify the TUI of the new size
		window.resize_pty(term_buf, term_win, 0)
	end

	term_data.is_fullscreen = is_fullscreen
	window.set_nav_keymaps_enabled(term_buf, not is_fullscreen)
end

--- Hide terminal window (keeps process alive)
--- @param term_buf number|nil The terminal buffer (if nil, uses current terminal)
--- @return nil
function M.hide_terminal(term_buf)
	term_buf = term_buf or M.get_current_terminal_buf()
	if not term_buf then
		return
	end

	local name = M.buf_to_name[term_buf]
	local term_data = name and M.terminals[name]
	debug.log("hide_terminal", function()
		return { name = name, term_buf = term_buf }
	end)

	if not term_data or not term_data.cli_term then
		return
	end

	local term_win = nil
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == term_buf then
			term_win = win
			break
		end
	end

	if term_win and vim.api.nvim_win_is_valid(term_win) then
		vim.api.nvim_win_close(term_win, false)
	end
end

--- Close terminal window and kill the process
--- @param term_buf number|nil The terminal buffer (if nil, uses current terminal)
--- @return nil
function M.close_terminal(term_buf)
	term_buf = term_buf or M.get_current_terminal_buf()
	if not term_buf then
		return
	end

	local name = M.buf_to_name[term_buf]
	debug.log("close_terminal", function()
		return { name = name, term_buf = term_buf }
	end)
	local term_data = name and M.terminals[name]

	if not term_data or not term_data.cli_term then
		local term_win = nil
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(win) == term_buf then
				term_win = win
				break
			end
		end

		if term_win and vim.api.nvim_win_is_valid(term_win) then
			vim.api.nvim_win_close(term_win, true)
		end

		if vim.api.nvim_buf_is_valid(term_buf) then
			local ok, job_id = pcall(vim.api.nvim_buf_get_var, term_buf, "terminal_job_id")
			if ok and job_id then
				vim.fn.jobstop(job_id)
			end
			vim.api.nvim_buf_delete(term_buf, { force = true })
		end
		return
	end

	local job_id = term_data.cli_term.job_id

	local term_win = nil
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == term_buf then
			term_win = win
			break
		end
	end

	if term_win and vim.api.nvim_win_is_valid(term_win) then
		vim.api.nvim_win_close(term_win, true)
	end

	if job_id and job_id > 0 then
		vim.fn.jobstop(job_id)
	end

	if vim.api.nvim_buf_is_valid(term_buf) then
		vim.api.nvim_buf_delete(term_buf, { force = true })
	end

	M.terminals[name] = nil
	M.buf_to_name[term_buf] = nil
end

--- Find the window displaying a terminal buffer
--- @param term_buf number The terminal buffer handle
--- @return number|nil win_id or nil if not visible
function M.find_terminal_window(term_buf)
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == term_buf then
			return win
		end
	end
	return nil
end

--- Get the job_id for a terminal buffer (handles both old and new Neovim APIs)
--- @param term_buf number The terminal buffer handle
--- @return number|nil job_id or nil
function M.get_terminal_job_id(term_buf)
	if not term_buf or not vim.api.nvim_buf_is_valid(term_buf) then
		return nil
	end
	-- Try Neovim >= 0.11 buffer variable first
	local ok, job_id = pcall(vim.api.nvim_buf_get_var, term_buf, "terminal_job_id")
	if ok and job_id then
		return job_id
	end
	-- Fallback: try vim.b (current buffer only, but may work if term_buf is current)
	ok, job_id = pcall(function()
		return vim.b.terminal_job_id
	end)
	if ok and job_id then
		return job_id
	end
	return nil
end

--- Focus the window containing a terminal buffer and enter insert mode
--- @return nil
--- @param term_buf number The terminal buffer handle
function M.focus_terminal_window(term_buf)
	local win = M.find_terminal_window(term_buf)
	debug.log("focus_terminal", function()
		return { buf = term_buf, valid = win ~= nil }
	end)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
		pcall(function()
			vim.cmd("startinsert")
		end)
	end
end

return M
