--- Ask hook module — captures context, shows input, sends to terminal
local M = {}
local debug = require("cli-integration.debug")

--- Capture current editing context (file, cursor, visual selection)
--- Must be called BEFORE any window/mode changes.
--- @param screen_capture table|nil {row, col} to store screen position into (optional)
--- @return Cli-Integration.AskData
local function capture_context(screen_capture)
	if screen_capture then
		screen_capture.row = vim.fn.screenrow()
		screen_capture.col = vim.fn.screencol()
	end

	local file = vim.fn.expand("%:p")
	local relative_file = vim.fn.expand("%")
	local filename = vim.fn.expand("%:t")
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_line = cursor[1]
	local filetype = vim.bo.filetype
	local mode = vim.api.nvim_get_mode().mode
	local selection = nil
	local start_line = cursor_line
	local end_line = cursor_line

	if mode:match("[vV\22]") then
		local v_start = vim.fn.getpos("v")
		local v_end = vim.fn.getpos(".")
		if v_start[2] > 0 and v_end[2] > 0 then
			start_line = math.min(v_start[2], v_end[2])
			end_line = math.max(v_start[2], v_end[2])
		end
		local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
		selection = table.concat(lines, "\n")
	end

	return {
		file = file,
		relative_file = relative_file,
		filename = filename,
		start_line = start_line,
		end_line = end_line,
		selection = selection,
		filetype = filetype,
	}
end

--- Floating input built from two windows:
---   outer — border + title + "❯ " icon (non-editable, non-focusable)
---   inner — actual text input, overlaid after the icon inside the outer window
---
--- @param title string
--- @param screen_row number 1-indexed screen row
--- @param screen_col number 1-indexed screen col
--- @param on_submit fun(text: string)
--- @param on_cancel fun()
local function show_input(title, screen_row, screen_col, on_submit, on_cancel)
	local icon = "❯ "
	local icon_cols = 2
	local total_width = math.min(60, vim.o.columns - 4)
	local height = 1

	local row = (screen_row - 1) + 1
	local col = (screen_col - 1) - math.floor(total_width / 2)
	col = math.max(0, math.min(col, vim.o.columns - total_width - 2))
	if row + height + 2 > vim.o.lines - 1 then
		row = math.max(0, (screen_row - 1) - height - 2)
	end

	local outer_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[outer_buf].buftype = "nofile"
	vim.bo[outer_buf].bufhidden = "wipe"
	vim.api.nvim_buf_set_lines(outer_buf, 0, -1, false, { " " .. icon })
	vim.bo[outer_buf].modifiable = false
	local ns = vim.api.nvim_create_namespace("cli-integration-ask")
	vim.api.nvim_buf_set_extmark(outer_buf, ns, 0, 1, { hl_group = "Keyword", end_col = 3 })

	local outer_win = vim.api.nvim_open_win(outer_buf, false, {
		relative = "editor",
		row = row,
		col = col,
		width = total_width,
		height = height,
		border = "rounded",
		title = " " .. title .. " ",
		title_pos = "center",
		style = "minimal",
		focusable = false,
		zindex = 50,
	})

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "win",
		win = outer_win,
		row = 0,
		col = icon_cols + 1,
		width = total_width - icon_cols - 1,
		height = height,
		border = "none",
		style = "minimal",
		zindex = 51,
	})

	local submitted = false
	local opts = { buffer = buf, nowait = true, silent = true }

	local function close_all()
		pcall(vim.api.nvim_win_close, win, true)
		pcall(vim.api.nvim_win_close, outer_win, true)
	end

	vim.keymap.set("i", "<CR>", function()
		if submitted then
			return
		end
		submitted = true
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local text = vim.trim(table.concat(lines, "\n"))
		close_all()
		if text ~= "" then
			on_submit(text)
		else
			on_cancel()
		end
	end, opts)

	vim.keymap.set("i", "<Esc>", function()
		debug.log("ask_cancel", function()
			return { title = title }
		end)
		close_all()
		vim.cmd("stopinsert")
		on_cancel()
	end, opts)

	vim.keymap.set("n", "<Esc>", function()
		debug.log("ask_cancel", function()
			return { title = title }
		end)
		close_all()
		on_cancel()
	end, opts)

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			pcall(vim.api.nvim_win_close, outer_win, true)
		end,
	})

	vim.cmd("startinsert")
end

--- Look up integration by name, index, or cli_cmd
--- @param identifier string|number|nil
--- @return Cli-Integration.Integration|nil
--- @return string|nil error message
local function lookup_integration(identifier)
	local config = require("cli-integration.config")
	local integrations = config.options.integrations or {}

	if #integrations == 0 then
		return nil, "No integrations configured."
	end

	if not identifier then
		return integrations[1], nil
	end

	if type(identifier) == "number" then
		if identifier < 1 or identifier > #integrations then
			return nil, "Integration index " .. identifier .. " out of range (1-" .. #integrations .. ")"
		end
		return integrations[identifier], nil
	elseif type(identifier) == "string" then
		local normalized = identifier:gsub("_", " ")
		for _, integration in ipairs(integrations) do
			if integration.name == normalized or integration.name == identifier then
				return integration, nil
			end
		end
		for _, integration in ipairs(integrations) do
			if integration.cli_cmd == identifier then
				return integration, nil
			end
		end
		return nil, "Integration '" .. identifier .. "' not found"
	end

	return nil, "Invalid identifier type"
end

--- Open or toggle the integration terminal (no callbacks, no start_with_text overrides).
--- @param integration Cli-Integration.Integration
local function open_integration(integration)
	local terminal = require("cli-integration.terminal")
	local name = integration.name
	local term_data = terminal.terminals[name]

	if term_data and term_data.term_buf and vim.api.nvim_buf_is_valid(term_data.term_buf) then
		local term_win = terminal.find_terminal_window(term_data.term_buf)
		if not term_win and term_data.cli_term and term_data.cli_term.toggle then
			term_data.cli_term:toggle()
		end
	else
		-- Suppress start_with_text so ask's question takes priority
		local saved_start = integration.start_with_text
		integration.start_with_text = function()
			integration.start_with_text = saved_start
			return ""
		end

		local working_dir = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
		if not working_dir or working_dir == "" then
			working_dir = vim.fn.expand("%:p:h")
			if working_dir == "" then
				working_dir = vim.fn.getcwd()
			end
		end
		terminal.open_terminal(integration, nil, integration.keep_open, working_dir)
	end
end

--- Build the actions table and call on_ask_submit once the terminal is ready.
--- @param integration Cli-Integration.Integration
--- @param context Cli-Integration.AskData
--- @param question string
local function _handle_submit(integration, context, question)
	context.question = question

	debug.log("ask_submit", function()
		return {
			integration_name = integration and integration.name or "unknown",
			question_length = #question,
			has_selection = context.selection ~= nil,
		}
	end)

	local terminal = require("cli-integration.terminal")
	local term_data = terminal.terminals[integration.name]
	if not term_data or not term_data.term_buf then
		return
	end
	local term_buf = term_data.term_buf
	local focused_file = false
	local co = nil

	local actions = {
		send_line = function(text)
			require("cli-integration.terminal").insert_text((text or "") .. "\n", term_buf)
		end,
		send_keys = function(keys)
			local converted = vim.api.nvim_replace_termcodes(keys, true, true, true)
			require("cli-integration.terminal").insert_text(converted, term_buf)
		end,
		wait = function(ms)
			vim.defer_fn(function()
				if co and coroutine.status(co) == "suspended" then
					coroutine.resume(co)
				end
			end, ms)
			coroutine.yield()
		end,
		submit = function()
			vim.defer_fn(function()
				local job_id = terminal.get_terminal_job_id(term_buf)
				if job_id and vim.fn.jobwait({ job_id }, 10)[1] == -1 then
					vim.fn.chansend(job_id, "\r")
				end
			end, 50)
		end,
		focus_file = function()
			focused_file = true
			for _, w in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_is_valid(w) then
					local b = vim.api.nvim_win_get_buf(w)
					if vim.bo[b].buftype == "" and vim.bo[b].buflisted then
						pcall(vim.api.nvim_set_current_win, w)
						pcall(function()
							vim.cmd("stopinsert")
						end)
						return
					end
				end
			end
		end,
	}

	local function apply_focus_file()
		if focused_file then
			for _, w in ipairs(vim.api.nvim_list_wins()) do
				if vim.api.nvim_win_is_valid(w) then
					local b = vim.api.nvim_win_get_buf(w)
					if vim.bo[b].buftype == "" and vim.bo[b].buflisted then
						pcall(vim.api.nvim_set_current_win, w)
						pcall(function()
							vim.cmd("stopinsert")
						end)
						return
					end
				end
			end
		end
	end

	local function run_callback()
		-- Focus terminal first so user sees the actions execute
		terminal.focus_terminal_window(term_buf)

		local on_ask = integration.on_ask_submit
		if on_ask and type(on_ask) == "function" then
			co = coroutine.create(function()
				local ok, err = pcall(on_ask, context, actions)
				if not ok then
					vim.notify("cli-integration.nvim: on_ask_submit error: " .. tostring(err), vim.log.levels.ERROR)
				end
				apply_focus_file()
			end)
			coroutine.resume(co)
		else
			local default_fn = require("cli-integration.config").options.on_ask_submit
			if default_fn then
				default_fn(context, actions)
			end
			apply_focus_file()
		end
	end

	run_callback()
end

--- Ask a question to a CLI integration.
--- Sequential flow: capture → open terminal → return to file → restore selection → show input.
--- @param integration_identifier string|number|nil
function M.ask(integration_identifier)
	local screen_cap = {}
	local context = capture_context(screen_cap)

	local integration, err = lookup_integration(integration_identifier)

	debug.log("ask_open", function()
		return { integration_name = integration and integration.name or "unknown" }
	end)

	if not integration then
		vim.notify("cli-integration.nvim: " .. (err or "integration not found"), vim.log.levels.WARN)
		return
	end

	local title = integration.ask_title or ("Ask " .. integration.name)

	-- Step 2: Open the integration terminal (steals focus, enters normal mode — expected)
	open_integration(integration)

	-- Step 3: Return to the file buffer
	local file_win = nil
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(w) then
			local b = vim.api.nvim_win_get_buf(w)
			if vim.bo[b].buftype == "" and vim.bo[b].buflisted then
				file_win = w
				break
			end
		end
	end

	if file_win then
		pcall(vim.api.nvim_set_current_win, file_win)
	end

	-- Step 4: Restore visual selection if there was one
	if context.selection then
		vim.api.nvim_win_set_cursor(0, { context.start_line, 0 })
		vim.cmd("normal! V")
		vim.api.nvim_win_set_cursor(0, { context.end_line, 0 })
	end

	-- Step 5: Show the input in insert mode
	-- Delay ensures the terminal's scheduled stopinsert (from WinLeave when we
	-- returned focus to the file window) runs before we enter insert mode.
	vim.defer_fn(function()
		show_input(title, screen_cap.row, screen_cap.col, function(question)
			_handle_submit(integration, context, question)
		end, function() end)
	end, 50)
end

return M
