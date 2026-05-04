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
---   split_win = number,
---   split_buf = number,
---   terminal_buf = number,
---   width_config = number,
---   padding = number,
---   win_opts = table,
---   is_expanded = boolean,
---   list_buffer = boolean,
--- }
M.sidebars = {}

--- Helper predicates for window classification

--- Check if a window is a sidebar proxy split (navigation-only, no content)
--- @param win number Window handle
--- @return boolean
local function is_sidebar_split_win(win)
	for _, data in pairs(M.sidebars) do
		if data.split_win == win then
			return true
		end
	end
	return false
end

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

--- Check if a window is an integration proxy split for a given terminal buffer
--- @param win number Window handle
--- @param term_buf number Terminal buffer
--- @return boolean
local function is_integration_proxy_split(win, term_buf)
	local float_win = find_sidebar_float_by_term_buf(term_buf)
	if float_win then
		local data = M.sidebars[float_win]
		return data ~= nil and data.split_win == win
	end
	return false
end

--- Check if a window is any integration window (float or proxy split) for a given terminal buffer
--- @param win number Window handle
--- @param term_buf number Terminal buffer
--- @return boolean
local function is_integration_window(win, term_buf)
	return is_integration_float_win(win, term_buf) or is_integration_proxy_split(win, term_buf)
end

local function is_valid_win(win)
	return type(win) == "number" and win > 0 and vim.api.nvim_win_is_valid(win)
end

local function is_valid_buf(buf)
	return type(buf) == "number" and buf > 0 and vim.api.nvim_buf_is_valid(buf)
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

--- Find a safe anchor window in the normal layout (non-float/non-proxy)
--- for creating/recreating sidebar proxy splits.
--- @return number|nil
local function find_layout_anchor_window()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and not M.sidebars[win] and not is_sidebar_split_win(win) then
			local cfg = vim.api.nvim_win_get_config(win)
			if cfg.relative == "" then
				local buf = vim.api.nvim_win_get_buf(win)
				local bt = vim.bo[buf].buftype
				if bt == "" then
					return win
				end
			end
		end
	end

	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and not M.sidebars[win] and not is_sidebar_split_win(win) then
			local cfg = vim.api.nvim_win_get_config(win)
			if cfg.relative == "" then
				return win
			end
		end
	end

	return nil
end

--- Track if resize autocmd is setup
M.resized_autocmd_setup = false

--- Suppress stopinsert scheduling during proxy split recreation to preserve insert mode
M._suppress_stopinsert = false

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

local function compute_sidebar_target_geometry(data, split_win)
	-- data: M.sidebars[float_win]
	local padding = data.padding or 0
	local border = data.win_opts and data.win_opts.border or "none"
	local border_offset = (border == "none" or border == "") and 0 or 2

	local width
	if split_win and vim.api.nvim_win_is_valid(split_win) then
		-- Use observed split width as source of truth
		width = vim.api.nvim_win_get_width(split_win)
	else
		local configured = calculate_width(data.width_config)
		width = configured - (padding * 2)
	end

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

local function apply_split_width(split_win, width)
	if split_win and vim.api.nvim_win_is_valid(split_win) then
		pcall(vim.api.nvim_win_set_width, split_win, width)
	end
end

local function ensure_split_inert(split_win, split_buf)
	if not split_buf or not vim.api.nvim_buf_is_valid(split_buf) then
		return
	end
	-- Buffer properties
	vim.bo[split_buf].bufhidden = "wipe"
	vim.bo[split_buf].buflisted = false
	vim.bo[split_buf].buftype = "nofile"
	vim.bo[split_buf].swapfile = false
	vim.bo[split_buf].modifiable = false
	-- Window properties
	if split_win and vim.api.nvim_win_is_valid(split_win) then
		vim.wo[split_win].winfixwidth = true
		vim.wo[split_win].number = false
		vim.wo[split_win].relativenumber = false
		vim.wo[split_win].statuscolumn = ""
		vim.wo[split_win].signcolumn = "no"
		vim.wo[split_win].cursorline = false
		vim.wo[split_win].cursorcolumn = false
	end
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

--- Create a proxy split window (no buffer, just for navigation)
--- @param width number Width of the split
--- @param float_win number Associated floating window
--- @return number split_win The split window handle
--- @return number split_buf The split buffer handle
local function create_proxy_split(width, float_win)
	-- Create split on the right from a stable layout window to avoid
	-- competing with special sidebars (e.g. neo-tree) when restoring.
	local prev_layout_win = vim.api.nvim_get_current_win()
	local anchor_win = find_layout_anchor_window()
	if anchor_win and vim.api.nvim_win_is_valid(anchor_win) then
		pcall(vim.api.nvim_set_current_win, anchor_win)
	end
	vim.cmd("botright vsplit")
	local split_win = vim.api.nvim_get_current_win()

	-- Create an empty scratch buffer
	local split_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(split_win, split_buf)
	vim.api.nvim_win_set_width(split_win, width)

	-- Configure split window to be a navigation proxy
	vim.wo[split_win].winfixwidth = true
	vim.wo[split_win].number = false
	vim.wo[split_win].relativenumber = false
	vim.wo[split_win].statuscolumn = ""
	vim.wo[split_win].signcolumn = "no"
	vim.wo[split_win].cursorline = false
	vim.wo[split_win].cursorcolumn = false

	-- Configure buffer to prevent any content
	vim.bo[split_buf].bufhidden = "wipe"
	vim.bo[split_buf].buflisted = false
	vim.bo[split_buf].buftype = "nofile"
	vim.bo[split_buf].swapfile = false
	vim.bo[split_buf].modifiable = false
	ensure_split_inert(split_win, split_buf)

	if is_valid_win(prev_layout_win) then
		pcall(vim.api.nvim_set_current_win, prev_layout_win)
	end

	-- Navigation: entering the split redirects to the float
	vim.api.nvim_create_autocmd("WinEnter", {
		buffer = split_buf,
		callback = function()
			local current_win = vim.api.nvim_get_current_win()
			local target_float = float_win

			-- If float_win was not provided or is invalid, try to find it in M.sidebars
			if not target_float or target_float == 0 or not vim.api.nvim_win_is_valid(target_float) then
				for fw, data in pairs(M.sidebars) do
					if data.split_win == current_win then
						target_float = fw
						break
					end
				end
			end

			if target_float and vim.api.nvim_win_is_valid(target_float) then
				local ok_prev, prev_win_id = pcall(function()
					return vim.fn.win_getid(vim.fn.winnr("#"))
				end)
				if not ok_prev then
					prev_win_id = nil
				end
				if prev_win_id == target_float then
					-- We came from the float, move left to avoid getting stuck
					-- Check if there's a window to the left
					local ok2, left_winnr = pcall(function()
						return vim.fn.winnr("h")
					end)
					if ok2 and left_winnr ~= vim.fn.winnr() then
						pcall(vim.cmd.wincmd, "h")
					else
						-- Nowhere to go, return to float
						pcall(vim.api.nvim_set_current_win, target_float)
						vim.schedule(function()
							if is_valid_win(target_float) then
								vim.cmd("startinsert")
							end
						end)
					end
				else
					-- We came from elsewhere, go to float
					pcall(vim.api.nvim_set_current_win, target_float)
					vim.schedule(function()
						if is_valid_win(target_float) then
							vim.cmd("startinsert")
						end
					end)
				end
			end
		end,
		desc = "Redirect split navigation to float window",
	})

	-- Prevent closing the split directly - close the float instead
	vim.api.nvim_create_autocmd("QuitPre", {
		buffer = split_buf,
		callback = function()
			local current_win = vim.api.nvim_get_current_win()
			local target_float = float_win

			-- Dynamic lookup if float_win is not set
			if not target_float or target_float == 0 or not vim.api.nvim_win_is_valid(target_float) then
				for fw, data in pairs(M.sidebars) do
					if data.split_win == current_win then
						target_float = fw
						break
					end
				end
			end

			if target_float and vim.api.nvim_win_is_valid(target_float) then
				vim.schedule(function()
					if vim.api.nvim_win_is_valid(target_float) then
						vim.api.nvim_win_close(target_float, false)
					end
				end)
				return true -- Cancel the quit of the split
			end
		end,
		desc = "Redirect split close to float close",
	})

	return split_win, split_buf
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
					-- Skip sidebar proxy splits using is_sidebar_split_win.
					local target_win = nil
					local fallback_win = nil
					for _, w in ipairs(vim.api.nvim_list_wins()) do
						if w ~= current_win and vim.api.nvim_win_is_valid(w) then
							local b = vim.api.nvim_win_get_buf(w)
							local bt = vim.bo[b].buftype
							if not is_sidebar_split_win(w) then
								if bt == "" then
									target_win = w
									break
								elseif not fallback_win and bt ~= "terminal" and bt ~= "nofile" then
									fallback_win = w
								end
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
	-- Never force terminal buffer into proxy split windows.
	vim.api.nvim_create_autocmd("WinEnter", {
		callback = function()
			local current_win = vim.api.nvim_get_current_win()
			-- Only guard if current window is the integration float window.
			-- Proxy split must stay inert/nofile and never receive terminal buffer.
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
			if M._suppress_stopinsert then
				return
			end
			vim.schedule(function()
				vim.cmd("stopinsert")
			end)
		end,
		desc = "Exit insert mode when leaving terminal window",
	})

	vim.cmd("startinsert")
	return win
end

--- Create the Sidebar layout (proxy split + floating terminal)
--- @param buf number Terminal buffer
--- @param win_opts table Window options
--- @return number|nil The floating window handle
function M.create_sidebar_layout(buf, win_opts)
	local width_config = win_opts.min_width or win_opts.width or 34
	local padding = win_opts.padding or 0
	local configured_width = calculate_width(width_config)

	-- Calculate widths: float width accounts for padding
	local float_width = configured_width - (padding * 2)
	local split_width = float_width

	-- Step 1: Create proxy split (reserves space, handles navigation)
	local split_win, split_buf = create_proxy_split(split_width, 0) -- Placeholder, will update

	-- Step 2: Create floating window over the split
	local float_opts = {
		relative = "editor",
		width = float_width,
		height = 10, -- Will be updated by update_sidebar_geometry
		row = 0,
		col = vim.o.columns - split_width,
		style = "minimal",
		border = win_opts.border or "none",
		title = win_opts.title or "",
		title_pos = "center",
		zindex = 45,
	}

	local float_win = vim.api.nvim_open_win(buf, true, float_opts)

	-- Step 3: Store sidebar configuration
	M.sidebars[float_win] = {
		split_win = split_win,
		split_buf = split_buf,
		terminal_buf = buf,
		width_config = width_config,
		win_opts = win_opts,
		padding = padding,
		is_expanded = false,
		list_buffer = win_opts.list_buffer or false,
	}

	-- Step 4: Update geometry to correct dimensions
	M.update_sidebar_geometry(float_win, false, true)

	-- Step 5: Cleanup when float closes
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(float_win),
		callback = function()
			local data = M.sidebars[float_win]
			if data then
				if is_valid_win(data.split_win) then
					vim.api.nvim_win_close(data.split_win, true)
				end
				if is_valid_buf(data.split_buf) then
					vim.api.nvim_buf_delete(data.split_buf, { force = true })
				end
				M.sidebars[float_win] = nil
			end
		end,
		once = true,
		desc = "Cleanup sidebar on float close",
	})

	-- Step 6: Exit insert mode when focus is lost
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

	-- Step 7: Setup resize handling (bidirectional sync)
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
		-- Fullwidth mode: hide split, expand float to full editor width

		-- Hide the proxy split
		if is_valid_win(data.split_win) then
			vim.api.nvim_win_close(data.split_win, true)
		end
		data.split_win = nil
		data.split_buf = nil

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
		-- Normal sidebar mode: show split, sync dimensions
		-- Recreate split if it was closed (e.g., after fullwidth toggle)
		if not is_valid_win(data.split_win) then
			local configured_width = calculate_width(data.width_config)
			local split_width = configured_width - (padding * 2)
			-- Suppress stopinsert while the split is being created: botright vsplit
			-- fires WinLeave on the float, which would otherwise schedule stopinsert
			-- and leave the terminal in normal mode after the toggle.
			M._suppress_stopinsert = true
			local split_win, split_buf = create_proxy_split(split_width, float_win)
			M._suppress_stopinsert = false
			data.split_win = split_win
			data.split_buf = split_buf
			ensure_split_inert(split_win, split_buf)
		end

		-- Re-enable window-navigation keymaps
		local nav_opts = { buffer = term_buf, noremap = true, silent = true }
		vim.keymap.set("t", "<C-h>", [[<C-\><C-n><Cmd>wincmd h<CR>]], nav_opts)
		vim.keymap.set("t", "<C-j>", [[<C-\><C-n><Cmd>wincmd j<CR>]], nav_opts)
		vim.keymap.set("t", "<C-k>", [[<C-\><C-n><Cmd>wincmd k<CR>]], nav_opts)
		vim.keymap.set("t", "<C-l>", [[<C-\><C-n><Cmd>wincmd l<CR>]], nav_opts)

		-- Compute geometry anchored to split and apply consistently
		local geom = compute_sidebar_target_geometry(data, data.split_win)
		-- synchronize split and float explicitly
		apply_split_width(data.split_win, geom.width)
		apply_float_geometry(float_win, geom)
		data.is_expanded = false
	end

	-- Focus if requested or already focused
	local current_win = vim.api.nvim_get_current_win()
	if (should_focus or current_win == float_win) and is_valid_win(float_win) then
		vim.api.nvim_set_current_win(float_win)
		-- Schedule startinsert so it runs after any pending stopinsert (e.g. from
		-- WinLeave fired during create_proxy_split). vim.schedule is FIFO, so this
		-- enqueues after the stopinsert already in the queue and wins.
		vim.schedule(function()
			if is_valid_win(float_win) then
				vim.cmd("startinsert")
			end
		end)
	end
end

--- Resize all sidebars (bidirectional sync)
--- Handles both editor resize and manual split resize
function M.resize_sidebars()
	for float_win, data in pairs(M.sidebars) do
		if is_valid_win(float_win) then
			-- Check if split is visible to determine mode
			local is_expanded = not is_valid_win(data.split_win)

			-- If split was manually resized, sync the float
			if not is_expanded and is_valid_win(data.split_win) then
				-- Sidebar mode: prefer observed split width as authoritative
				local geom = compute_sidebar_target_geometry(data, data.split_win)
				apply_float_geometry(float_win, geom)
				-- Reconcile split width to computed width (edge cases)
				apply_split_width(data.split_win, geom.width)
			else
				-- Editor resize or fullwidth: compute appropriate geometry
				if is_expanded then
					local geom = compute_fullwidth_geometry()
					apply_float_geometry(float_win, geom)
				end
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
