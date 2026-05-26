--- Window and terminal management using native Neovim API
--- @class TerminalWindow
--- @field buf number Buffer number
--- @field win number|nil Window number (floating window)
--- @field job_id number Job ID
--- @field cmd string Command being run
--- @field opts table Terminal options
--- @field on_close function|nil Callback when terminal closes
--- @field toggle function|nil
local M = {}

--- Store active sidebar configurations
--- Format: [float_win] = {
---   terminal_buf = number,
---   width_config = number,
---   win_opts = table,
---   padding = number,
---   is_expanded = boolean,
---   list_buffer = boolean,
--- }
M.sidebars = {}

--- Helper predicates for window classification

--- Find sidebar float by terminal buffer
--- @param term_buf number Terminal buffer
--- @return number|nil float_win or nil if not found
local function find_sidebar_float_by_term_buf(term_buf)
	for float_win, data in pairs(M.sidebars) do
		if data.terminal_buf == term_buf then
			return float_win
		end
	end
	return nil
end

--- Check if a window is an integration float window for a given terminal buffer
--- @param win number Window handle
--- @param term_buf number Terminal buffer
--- @return boolean
local function is_integration_float_win(win, term_buf)
	local data = M.sidebars[win]
	return data ~= nil and data.terminal_buf == term_buf
end

--- Check if a window is an integration window for a given terminal buffer
--- @param win number Window handle
--- @param term_buf number Terminal buffer
--- @return boolean
local function is_integration_window(win, term_buf)
	return is_integration_float_win(win, term_buf)
end

local function is_valid_win(win)
	return type(win) == "number" and win > 0 and vim.api.nvim_win_is_valid(win)
end

--- Build terminal job environment starting from inherited process env,
--- then applying explicit overrides and removals.
--- @param opts table
--- @param cols number
--- @param lines number
--- @return table<string, string>
local function build_job_env(opts, cols, lines)
	local env = vim.fn.environ()

	-- Always refresh dimensions from finalized geometry
	env.COLUMNS = tostring(cols)
	env.LINES = tostring(lines)

	-- Optional explicit overrides
	if type(opts.env) == "table" then
		env = vim.tbl_extend("force", env, opts.env)
	end

	-- Optional removals after merge
	if type(opts.unset_env) == "table" then
		for _, key in ipairs(opts.unset_env) do
			env[key] = nil
		end
	end

	return env
end

--- Track if resize autocmd is setup
M.resized_autocmd_setup = false

--- Suppress stopinsert during toggle operations
M._suppress_stopinsert = false

--- Track last known editor width to distinguish editor resize from manual split resize
M._last_editor_width = vim.o.columns

--- Calculate width based on config (percentage or absolute)
--- @param width_config number Width configuration (1-100 for percentage, >100 for absolute)
--- @return number Calculated width in columns
local function calculate_width(width_config)
	local editor_width = vim.o.columns
	if width_config <= 100 then
		local percentage = width_config <= 1 and width_config or (width_config / 100)
		return math.floor(editor_width * percentage)
	end
	return width_config
end

-- Geometry engine helpers (local, internal)
local function compute_fullwidth_geometry()
	local border_offset = 2
	local width = vim.o.columns - border_offset
	local col = 1
	local height = vim.o.lines - vim.o.cmdheight - border_offset - 1
	local row = 0
	return { width = width, height = height, col = col, row = row, border = "rounded", border_offset = border_offset }
end

local function compute_sidebar_target_geometry(data)
	-- data: M.sidebars[float_win]
	local padding = data.padding or 0
	local border = data.win_opts and data.win_opts.border or "none"
	local border_offset = (border == "none" or border == "") and 0 or 2

	local configured = calculate_width(data.width_config)
	local width = configured - (padding * 2)

	local col = vim.o.columns - width
	local height = vim.o.lines - vim.o.cmdheight - border_offset - 1
	local row = 0
	return { width = width, height = height, col = col, row = row, border = border, border_offset = border_offset }
end

local function apply_float_geometry(float_win, geom)
	if not vim.api.nvim_win_is_valid(float_win) then
		return
	end
	local cfg = {
		relative = "editor",
		width = geom.width,
		height = geom.height,
		row = geom.row or 0,
		col = geom.col or 0,
		style = "minimal",
		border = geom.border or "none",
		zindex = 45,
	}
	pcall(vim.api.nvim_win_set_config, float_win, cfg)
end

--- Calculate the usable content dimensions of a terminal window,
--- subtracting border cells, padding, and optional list_buffer row offset.
--- @param win number Window handle (must be valid and sized)
--- @param border string|table Border style ("none"|"single"|"double"|"rounded"|"solid"|"shadow") or 8-element array
--- @param padding number Horizontal padding in columns (foldcolumn)
--- @param list_buffer boolean Whether the list_buffer row offset is active
--- @return number cols  Usable columns (COLUMNS env var)
--- @return number lines Usable lines  (LINES env var)
local function calculate_content_dimensions(win, border, padding, list_buffer)
	local w = vim.api.nvim_win_get_width(win)
	local h = vim.api.nvim_win_get_height(win)
	local border_offset
	if type(border) == "table" then
		border_offset = (#border > 0) and 2 or 0
	else
		border_offset = (border == nil or border == "none" or border == "") and 0 or 2
	end
	local row_offset = (list_buffer == true) and 1 or 0
	local cols = math.max(1, w - border_offset - (padding * 2))
	local lines = math.max(1, h - border_offset - row_offset)
	return cols, lines
end

--- Create a new terminal window
--- @param cmd string Command to run in terminal
--- @param opts table Options for terminal creation
--- @return TerminalWindow|nil
function M.create_terminal(cmd, opts)
	opts = opts or {}
	local win_opts = opts.win or {}
	local cwd = opts.cwd or vim.fn.getcwd()
	local auto_close = opts.auto_close ~= false

	-- Create terminal buffer
	local buf = vim.api.nvim_create_buf(false, true)
	if not buf or buf == 0 then
		return nil
	end

	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].buflisted = false

	-- Set buffer variable for integration identification BEFORE termopen/jobstart
	-- so TermOpen autocmds can identify which integration this terminal belongs to.
	if win_opts.integration_name and win_opts.integration_name ~= "" then
		vim.api.nvim_buf_set_var(buf, "cli_integration_name", win_opts.integration_name)
	end

	-- Create window based on position
	local is_float = win_opts.position == "float"
	local win

	if is_float then
		win = M.create_float_window(buf, win_opts)
	else
		win = M.create_sidebar_layout(buf, win_opts)
	end

	if not win then
		vim.api.nvim_buf_delete(buf, { force = true })
		return nil
	end

	-- Configure window options
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].spell = false
	vim.wo[win].cursorline = false

	-- Create terminal object
	---@type TerminalWindow
	local terminal = {
		buf = buf,
		win = win,
		job_id = 0,
		cmd = cmd,
		opts = opts,
		on_close = win_opts.on_close,
	}

	terminal.toggle = function()
		M.toggle_terminal(terminal)
	end

	-- Read final content dimensions AFTER geometry is established.
	-- create_sidebar_layout calls update_sidebar_geometry before returning, so
	-- win dimensions are correct here. Using calculate_content_dimensions ensures
	-- we subtract border cells, padding, and list_buffer row offset.
	local padding = win_opts.padding or 0
	local border = win_opts.border or (is_float and "rounded" or "none")
	local list_buf_flag = win_opts.list_buffer or false
	local cols, lines = calculate_content_dimensions(win, border, padding, list_buf_flag)

	-- Start terminal job
	local job_id
	vim.api.nvim_buf_call(buf, function()
		local original_cwd = vim.fn.getcwd()
		if cwd and cwd ~= "" then
			vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
		end

		local env = build_job_env(opts, cols, lines)

		local use_jobstart = vim.fn.has("nvim-0.11") == 1
		local job_opts = {
			cwd = cwd,
			env = env,
			term = true,
			on_exit = function(_, exit_code, _)
				if auto_close and exit_code == 0 then
					vim.schedule(function()
						local title = (win_opts.title ~= "" and win_opts.title) or "cli"
						local msg = "... bye bye" .. title .. " "
						local notif_buf = vim.api.nvim_create_buf(false, true)
						vim.api.nvim_buf_set_lines(notif_buf, 0, -1, false, { msg })
						local width = #msg
						local notif_win = vim.api.nvim_open_win(notif_buf, false, {
							relative = "editor",
							width = width,
							height = 1,
							row = vim.o.lines - 4,
							col = vim.o.columns - width - 2,
							style = "minimal",
							border = "rounded",
							focusable = false,
						})
						vim.defer_fn(function()
							pcall(vim.api.nvim_win_close, notif_win, true)
							pcall(vim.api.nvim_buf_delete, notif_buf, { force = true })
						end, 1000)
					end)
					vim.defer_fn(function()
						if vim.api.nvim_buf_is_valid(buf) then
							vim.api.nvim_buf_delete(buf, { force = true })
						end
					end, 1000)
				end
				if win_opts.on_close then
					vim.schedule(win_opts.on_close)
				end
			end,
		}

		if use_jobstart then
			job_id = vim.fn.jobstart(cmd, job_opts)
		else
			job_opts.term = nil
			---@diagnostic disable-next-line: deprecated
			job_id = vim.fn.termopen(cmd, job_opts)
		end

		vim.cmd("lcd " .. vim.fn.fnameescape(original_cwd))
	end)

	-- Apply padding
	if padding > 0 then
		vim.wo[win].foldcolumn = tostring(padding)
	end

	if not job_id or job_id <= 0 then
		vim.api.nvim_win_close(win, true)
		vim.api.nvim_buf_delete(buf, { force = true })
		return nil
	end

	terminal.job_id = job_id

	-- List buffer in bufferline if configured (must be after termopen so buftype=terminal is set)
	if opts.win and opts.win.list_buffer then
		vim.bo[buf].buflisted = true
	end

	-- Set/re-apply buffer name after termopen/jobstart (Neovim overwrites with term://...)
	if win_opts.buffer_name and win_opts.buffer_name ~= "" then
		pcall(vim.api.nvim_buf_set_name, buf, win_opts.buffer_name)
	end

	-- Setup terminal navigation keymaps (Ctrl+hjkl to navigate between windows)
	local keymap_opts = { buffer = buf, noremap = true, silent = true }
	vim.keymap.set("t", "<C-h>", [[<C-\><C-n><Cmd>wincmd h<CR>]], keymap_opts)
	vim.keymap.set("t", "<C-j>", [[<C-\><C-n><Cmd>wincmd j<CR>]], keymap_opts)
	vim.keymap.set("t", "<C-k>", [[<C-\><C-n><Cmd>wincmd k<CR>]], keymap_opts)
	vim.keymap.set("t", "<C-l>", [[<C-\><C-n><Cmd>wincmd l<CR>]], keymap_opts)

	-- Force insert mode on mouse click (if configured)
	-- Uses expr=true to check click position: only enter insert if click is inside
	-- this terminal window. If clicking outside, fall through to default mouse behavior
	-- (window focus change) by returning the built-in <LeftMouse> (noremap prevents recursion).
	if opts.win and opts.win.start_insert_on_click then
		local click_opts = { buffer = buf, noremap = true, silent = true, expr = true }
		local click_fn = function()
			local mouse_pos = vim.fn.getmousepos()
			local current_win = vim.api.nvim_get_current_win()
			-- Enter insert only if click is inside current window AND current window is integration window for this buf
			if mouse_pos.winid == current_win and is_integration_window(current_win, buf) then
				return "i"
			else
				return "<LeftMouse>"
			end
		end
		vim.keymap.set("n", "<LeftMouse>", click_fn, click_opts)
		vim.keymap.set("n", "<2-LeftMouse>", click_fn, click_opts)
	end

	-- Auto-enter insert mode when entering terminal
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
		buffer = buf,
		callback = function()
			if vim.bo[buf].buftype == "terminal" then
				vim.cmd("startinsert")
			end
		end,
		desc = "Auto-enter insert mode in terminal",
	})

	-- CRITICAL: Prevent buffer switching in this window
	-- This ensures the terminal window ONLY shows the terminal buffer.
	-- NOTE: `win` can become stale after a toggle (create_sidebar_layout creates a new float ID),
	-- so we also check M.sidebars dynamically for the current window.
	-- Also handles list_buffer edge case: if integration window is hidden and user selects buffer
	-- from bufferline, allow load in regular window without forcing insert mode.
	vim.api.nvim_create_autocmd("BufWinEnter", {
		callback = function(args)
			if args.buf == buf then
				return
			end

			local current_win = vim.api.nvim_get_current_win()
			local sidebar_data = M.sidebars[current_win]
			local is_our_win = current_win == win or (sidebar_data ~= nil and sidebar_data.terminal_buf == buf)

			-- Case 1: current_win is integration window and different buffer loaded
			if is_our_win then
				vim.schedule(function()
					if not vim.api.nvim_win_is_valid(current_win) or not vim.api.nvim_buf_is_valid(buf) then
						return
					end

					-- Restore the terminal buffer
					pcall(vim.api.nvim_win_set_buf, current_win, buf)

					-- Find a window to redirect the new buffer to.
					-- Priority: normal file window > any non-terminal/nofile window > new split.
					local target_win = nil
					local fallback_win = nil
					for _, w in ipairs(vim.api.nvim_list_wins()) do
						if w ~= current_win and vim.api.nvim_win_is_valid(w) then
							local b = vim.api.nvim_win_get_buf(w)
							local bt = vim.bo[b].buftype
							if bt == "" then
								target_win = w
								break
							elseif not fallback_win and bt ~= "terminal" and bt ~= "nofile" then
								fallback_win = w
							end
						end
					end

					local dest = target_win or fallback_win
					if not dest then
						-- Last resort: open a new split to host the buffer
						vim.cmd("vsplit")
						dest = vim.api.nvim_get_current_win()
					end

					if dest and vim.api.nvim_buf_is_valid(args.buf) then
						vim.api.nvim_set_current_win(dest)
						pcall(vim.api.nvim_win_set_buf, dest, args.buf)
					end
				end)
				return
			end

			-- Case 2: current_win is regular window and args.buf is terminal buffer
			if args.buf == buf then
				local float_win = find_sidebar_float_by_term_buf(buf)
				-- If visible integration float exists, focus it and start insert
				if float_win and vim.api.nvim_win_is_valid(float_win) then
					vim.api.nvim_set_current_win(float_win)
					vim.schedule(function()
						if vim.api.nvim_win_is_valid(float_win) then
							vim.cmd("startinsert")
						end
					end)
					-- Otherwise allow (window already has the terminal buffer in regular window)
				end
			end
		end,
		desc = "Lock terminal window to terminal buffer only; handle list_buffer window separation",
	})

	-- Secondary guard: if somehow a wrong buffer ends up in the terminal window
	-- on WinEnter, restore the terminal buffer immediately.
	-- Apply only when current window is the integration FLOAT window for this buf.
	vim.api.nvim_create_autocmd("WinEnter", {
		callback = function()
			local current_win = vim.api.nvim_get_current_win()
			-- Only guard if current window is the integration float window.
			if not is_integration_float_win(current_win, buf) then
				return
			end

			if
				vim.api.nvim_get_current_buf() ~= buf
				and vim.api.nvim_buf_is_valid(buf)
				and vim.api.nvim_win_is_valid(current_win)
			then
				pcall(vim.api.nvim_win_set_buf, current_win, buf)
			end
		end,
		desc = "Secondary guard: restore terminal buffer on WinEnter in integration window",
	})

	return terminal
end

--- Create a centered floating window
--- @param buf number Terminal buffer
--- @param win_opts table Window options
--- @return number|nil The floating window handle
function M.create_float_window(buf, win_opts)
	local width = win_opts.width or math.floor(vim.o.columns * 0.8)
	local height = win_opts.height or math.floor(vim.o.lines * 0.8)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local float_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = win_opts.border or "rounded",
		title = win_opts.title or "",
		title_pos = "center",
	}

	local win = vim.api.nvim_open_win(buf, true, float_opts)

	-- Exit insert mode when focus is lost
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = buf,
		callback = function()
			vim.schedule(function()
				vim.cmd("stopinsert")
			end)
		end,
		desc = "Exit insert mode when leaving terminal window",
	})

	vim.cmd("startinsert")
	return win
end

--- Create the Sidebar layout (floating terminal on right side, no proxy split)
--- @param buf number Terminal buffer
--- @param win_opts table Window options
--- @return number|nil The floating window handle
function M.create_sidebar_layout(buf, win_opts)
	local width_config = win_opts.min_width or win_opts.width or 34
	local padding = win_opts.padding or 0
	local configured_width = calculate_width(width_config)

	-- Calculate float width accounting for padding
	local float_width = configured_width - (padding * 2)

	-- Create floating window
	local float_opts = {
		relative = "editor",
		width = float_width,
		height = 10, -- Will be updated by update_sidebar_geometry
		row = 0,
		col = vim.o.columns - float_width,
		style = "minimal",
		border = win_opts.border or "none",
		title = win_opts.title or "",
		title_pos = "center",
		zindex = 45,
	}

	local float_win = vim.api.nvim_open_win(buf, true, float_opts)

	-- Store sidebar configuration
	M.sidebars[float_win] = {
		terminal_buf = buf,
		width_config = width_config,
		win_opts = win_opts,
		padding = padding,
		is_expanded = false,
		list_buffer = win_opts.list_buffer or false,
	}

	-- Update geometry to correct dimensions
	M.update_sidebar_geometry(float_win, false, true)

	-- Cleanup when float closes
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(float_win),
		callback = function()
			M.sidebars[float_win] = nil
		end,
		once = true,
		desc = "Cleanup sidebar on float close",
	})

	-- Exit insert mode when focus is lost
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = buf,
		callback = function()
			if M._suppress_stopinsert then
				return
			end
			vim.schedule(function()
				vim.cmd("stopinsert")
			end)
		end,
		desc = "Exit insert mode when leaving sidebar terminal",
	})

	-- Setup resize handling (bidirectional sync)
	-- Refresh cached editor width so resize detection starts from the current state.
	M._last_editor_width = vim.o.columns
	if not M.resized_autocmd_setup then
		local group = vim.api.nvim_create_augroup("CliIntegrationResize", { clear = true })
		vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
			group = group,
			callback = function()
				M.resize_sidebars()
				-- Cleanup if no sidebars remain
				if vim.tbl_count(M.sidebars) == 0 then
					pcall(vim.api.nvim_del_augroup_by_name, "CliIntegrationResize")
					M.resized_autocmd_setup = false
				end
			end,
			desc = "Sync sidebar and float dimensions on resize",
		})
		M.resized_autocmd_setup = true
	end

	vim.cmd("startinsert")
	return float_win
end

--- Update sidebar geometry (handles fullwidth toggle and resize sync)
--- @param float_win number The floating window handle
--- @param is_expanded boolean Whether to show at maximum width (fullwidth mode)
--- @param should_focus boolean|nil Whether to focus the window (default: false)
function M.update_sidebar_geometry(float_win, is_expanded, should_focus)
	local data = M.sidebars[float_win]
	if not data or not is_valid_win(float_win) then
		return
	end

	local padding = data.padding or 0

	local term_buf = data.terminal_buf

	if is_expanded then
		-- Fullwidth mode: expand float to full editor width

		-- Disable window-navigation keymaps (no other windows to navigate to)
		pcall(vim.keymap.del, "t", "<C-h>", { buffer = term_buf })
		pcall(vim.keymap.del, "t", "<C-j>", { buffer = term_buf })
		pcall(vim.keymap.del, "t", "<C-k>", { buffer = term_buf })
		pcall(vim.keymap.del, "t", "<C-l>", { buffer = term_buf })

		-- Use geometry helper for fullwidth
		local geom = compute_fullwidth_geometry()
		apply_float_geometry(float_win, geom)
		data.is_expanded = true
	else
		-- Normal sidebar mode: sync dimensions

		-- Re-enable window-navigation keymaps
		local nav_opts = { buffer = term_buf, noremap = true, silent = true }
		vim.keymap.set("t", "<C-h>", [[<C-\><C-n><Cmd>wincmd h<CR>]], nav_opts)
		vim.keymap.set("t", "<C-j>", [[<C-\><C-n><Cmd>wincmd j<CR>]], nav_opts)
		vim.keymap.set("t", "<C-k>", [[<C-\><C-n><Cmd>wincmd k<CR>]], nav_opts)
		vim.keymap.set("t", "<C-l>", [[<C-\><C-n><Cmd>wincmd l<CR>]], nav_opts)

		-- Compute geometry from width_config and apply
		local geom = compute_sidebar_target_geometry(data)
		apply_float_geometry(float_win, geom)
		data.is_expanded = false
	end

	-- Focus if requested or already focused
	local current_win = vim.api.nvim_get_current_win()
	if (should_focus or current_win == float_win) and is_valid_win(float_win) then
		vim.api.nvim_set_current_win(float_win)
		-- Schedule startinsert so it runs after any pending stopinsert.
		-- vim.schedule is FIFO, so this enqueues after any stopinsert
		-- already in the queue and wins.
		vim.schedule(function()
			if is_valid_win(float_win) then
				vim.cmd("startinsert")
			end
		end)
	end
end

--- Resize all sidebars
--- Distinguishes editor resize (recalculate from width_config) from other events.
function M.resize_sidebars()
	local editor_resized = vim.o.columns ~= M._last_editor_width
	if editor_resized then
		M._last_editor_width = vim.o.columns
	end

	for float_win, data in pairs(M.sidebars) do
		if is_valid_win(float_win) then
			if data.is_expanded then
				-- Fullwidth mode: always recompute from editor dimensions
				local geom = compute_fullwidth_geometry()
				apply_float_geometry(float_win, geom)
			else
				-- Sidebar mode: recalculate from configured width_config
				local geom = compute_sidebar_target_geometry(data)
				apply_float_geometry(float_win, geom)
			end
		else
			-- Cleanup invalid windows
			M.sidebars[float_win] = nil
		end
	end
end

--- Toggle terminal window visibility
--- @param terminal TerminalWindow Terminal object
--- @return nil
function M.toggle_terminal(terminal)
	if not terminal or not terminal.buf or not vim.api.nvim_buf_is_valid(terminal.buf) then
		return
	end

	if terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
		-- Close the terminal window
		vim.api.nvim_win_close(terminal.win, false)
		terminal.win = nil
	else
		-- Reopen the terminal window
		local win_opts = terminal.opts.win or {}
		local win

		if win_opts.position == "float" then
			win = M.create_float_window(terminal.buf, win_opts)
		else
			win = M.create_sidebar_layout(terminal.buf, win_opts)
		end

		if win then
			terminal.win = win
		end
	end
end

--- Check if a terminal window is visible
--- @param terminal TerminalWindow Terminal object
--- @return boolean
function M.is_terminal_visible(terminal)
	return terminal ~= nil and terminal.win ~= nil and vim.api.nvim_win_is_valid(terminal.win)
end

return M
