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
--- Format: [sidebar_win] = {
---   sidebar_win = number,      -- Vsplit window handle (or float in fullwidth mode)
---   terminal_buf = number,
---   width_config = number,
---   win_opts = table,
---   padding = number,
---   is_expanded = boolean,     -- true = fullwidth/float mode
---   list_buffer = boolean,
--- }
M.sidebars = {}

--- Helper predicates for window classification

--- Check if a window is an integration sidebar window for a given terminal buffer
--- @param win number Window handle
--- @param term_buf number Terminal buffer
--- @return boolean
local function is_integration_sidebar_win(win, term_buf)
	local data = M.sidebars[win]
	return data ~= nil and data.terminal_buf == term_buf
end

local function is_valid_win(win)
	return type(win) == "number" and win > 0 and vim.api.nvim_win_is_valid(win)
end

--- Resize the pty of a terminal job to match current window content dimensions.
--- Sends SIGWINCH so TUI apps update their internal size and mouse coordinates.
--- @param term_buf number Terminal buffer handle
--- @param win number Window handle (must be valid)
--- @param border string|table Border style
--- @param padding number Horizontal padding
local function resize_pty(term_buf, win, border, padding)
	local job_id = vim.bo[term_buf].channel
	if not job_id or job_id <= 0 then
		return
	end
	local w = vim.api.nvim_win_get_width(win)
	local h = vim.api.nvim_win_get_height(win)
	local border_offset
	if type(border) == "table" then
		border_offset = (#border > 0) and 2 or 0
	else
		border_offset = (border == nil or border == "none" or border == "") and 0 or 2
	end
	local content_width = math.max(1, w - border_offset - (padding * 2))
	local content_height = math.max(1, h - border_offset)
	pcall(vim.fn.jobresize, job_id, content_width, content_height)
end

--- Build terminal job environment starting from inherited process env,
--- then applying explicit overrides and removals.
---
--- TMUX/TERM_PROGRAM are stripped by default: the job runs inside a Neovim
--- pseudo-terminal, not inside tmux. Keeping them causes TUI apps (opencode,
--- lazygit, etc.) to enable tmux-specific behaviour such as bracketed paste
--- mode, which makes mouse selections in the host tmux session inject escape
--- sequences (\e[200~...\e[201~) as literal text into the application input.
--- @param opts table
--- @param cols number
--- @param lines number
--- @return table<string, string>
local function build_job_env(opts, cols, lines)
	local env = vim.fn.environ()

	-- Strip tmux identity vars: the job's pty is owned by Neovim, not tmux.
	-- Leaving TMUX/TERM_PROGRAM=tmux active causes bracketed-paste sequences
	-- from mouse selections to leak into the running TUI as literal text.
	env.TMUX = nil
	env.TMUX_PANE = nil
	env.TERM_PROGRAM = nil
	env.TERM_PROGRAM_VERSION = nil

	-- Strip Ghostty identity vars: the job runs inside Neovim :terminal, not Ghostty.
	-- Ghostty sets GHOSTTY_RESOURCES_DIR and TERMINFO pointing to its own terminfo.
	-- If the TUI library (e.g. crossterm via opencode) detects Ghostty through these
	-- vars, it enables Ghostty-specific escape sequences (e.g. SGR mouse mode 1016
	-- queries like ?1016$p) that Neovim's internal terminal emulator does not handle,
	-- resulting in visible garbage characters on startup. We also clear TERMINFO to
	-- prevent the job from loading Ghostty's custom terminfo directory.
	env.GHOSTTY_RESOURCES_DIR = nil
	env.GHOSTTY_SHELL_FEATURES = nil
	env.GHOSTTY_BIN_DIR = nil
	env.TERMINFO = nil

	-- Always refresh dimensions from finalized geometry
	env.COLUMNS = tostring(cols)
	env.LINES = tostring(lines)

	-- NOTE: Normalize TERM/COLORTERM to safe defaults for Neovim's :terminal.
	-- Host terminals like Ghostty set TERM=xterm-ghostty and expose identity vars
	-- (GHOSTTY_RESOURCES_DIR, etc.) that cause TUI apps to enable Ghostty-specific
	-- capabilities (e.g. SGR mouse mode 1016) that Neovim's internal terminal
	-- emulator does not fully handle. This causes visible garbage characters (e.g.
	-- "?1016$p") and can break mouse-based bracketed paste. We override to a
	-- universally compatible terminfo and strip Ghostty identity vars unless the
	-- user explicitly sets them via opts.env. Do NOT remove this normalization
	-- without testing inside Ghostty + tmux + Neovim :terminal with opencode/lazygit.
	if not (type(opts.env) == "table" and opts.env.TERM ~= nil) then
		env.TERM = "xterm-256color"
	end
	if not (type(opts.env) == "table" and opts.env.COLORTERM ~= nil) then
		env.COLORTERM = "truecolor"
	end

	-- Optional explicit overrides (can re-add any of the above if needed)
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

--- Calculate the usable content dimensions of a terminal window,
--- subtracting border cells and padding.
--- @param win number Window handle (must be valid and sized)
--- @param border string|table Border style ("none"|"single"|"double"|"rounded"|"solid"|"shadow") or 8-element array
--- @param padding number Horizontal padding in columns (foldcolumn)
--- @return number cols  Usable columns (COLUMNS env var)
--- @return number lines Usable lines  (LINES env var)
local function calculate_content_dimensions(win, border, padding)
	local w = vim.api.nvim_win_get_width(win)
	local h = vim.api.nvim_win_get_height(win)
	local border_offset
	if type(border) == "table" then
		border_offset = (#border > 0) and 2 or 0
	else
		border_offset = (border == nil or border == "none" or border == "") and 0 or 2
	end
	local cols = math.max(1, w - border_offset - (padding * 2))
	local lines = math.max(1, h - border_offset)
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
	-- create_sidebar_layout sets the vsplit width before returning, so
	-- win dimensions are correct here.
	local padding = win_opts.padding or 0
	local border = win_opts.border or (is_float and "rounded" or "none")
	local cols, lines = calculate_content_dimensions(win, border, padding)

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
			if mouse_pos.winid == current_win and is_integration_sidebar_win(current_win, buf) then
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
				-- Find the sidebar window for this terminal buffer via direct M.sidebars access
				local sidebar_win = nil
				for win_handle, data in pairs(M.sidebars) do
					if data.terminal_buf == buf then
						sidebar_win = win_handle
						break
					end
				end
				-- If visible integration sidebar exists, focus it and start insert
				if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
					vim.api.nvim_set_current_win(sidebar_win)
					vim.schedule(function()
						if vim.api.nvim_win_is_valid(sidebar_win) then
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
	-- Apply only when current window is the integration sidebar window for this buf.
	vim.api.nvim_create_autocmd("WinEnter", {
		callback = function()
			local current_win = vim.api.nvim_get_current_win()
			-- Only guard if current window is the integration sidebar window.
			if not is_integration_sidebar_win(current_win, buf) then
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

--- Find a safe anchor window in the normal layout for creating splits
--- @return number|nil
function M.find_layout_anchor_window()
	-- First pass: prefer a normal file buffer window (buftype == "")
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and not M.sidebars[win] then
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

	-- Second pass: any non-floating window
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and not M.sidebars[win] then
			local cfg = vim.api.nvim_win_get_config(win)
			if cfg.relative == "" then
				return win
			end
		end
	end

	return nil
end

--- Create the Sidebar layout (vsplit terminal on right side)
--- @param buf number Terminal buffer
--- @param win_opts table Window options
--- @return number|nil The vsplit window handle
function M.create_sidebar_layout(buf, win_opts)
	local width_config = win_opts.min_width or win_opts.width or 34
	local padding = win_opts.padding or 0
	local configured_width = calculate_width(width_config)

	-- Calculate vsplit width accounting for padding
	local vsplit_width = configured_width - (padding * 2)

	-- Create vsplit on the right side
	local anchor_win = M.find_layout_anchor_window()
	if anchor_win and vim.api.nvim_win_is_valid(anchor_win) then
		pcall(vim.api.nvim_set_current_win, anchor_win)
	end
	vim.cmd("botright vsplit")
	local sidebar_win = vim.api.nvim_get_current_win()

	-- Set the terminal buffer
	vim.api.nvim_win_set_buf(sidebar_win, buf)

	-- Apply the configured width BEFORE returning so that calculate_content_dimensions
	-- in create_terminal reads the correct (final) width, not whatever Neovim assigned
	-- from the botright vsplit (which is half the available space by default).
	-- This is the vsplit equivalent of the old float's update_sidebar_geometry() call.
	vim.api.nvim_win_set_width(sidebar_win, vsplit_width)

	-- Configure vsplit window
	vim.wo[sidebar_win].winfixwidth = true
	vim.wo[sidebar_win].number = false
	vim.wo[sidebar_win].relativenumber = false
	vim.wo[sidebar_win].signcolumn = "no"
	vim.wo[sidebar_win].cursorline = false
	vim.wo[sidebar_win].spell = false
	-- Use panel/sidebar highlight groups so background matches Snacks.terminal, neo-tree, etc.
	vim.wo[sidebar_win].winhighlight = "Normal:NormalSB,NormalNC:NormalSB,EndOfBuffer:NormalSB"

	-- Apply padding via foldcolumn
	if padding > 0 then
		vim.wo[sidebar_win].foldcolumn = tostring(padding)
	end

	-- Store sidebar configuration
	M.sidebars[sidebar_win] = {
		sidebar_win = sidebar_win,
		terminal_buf = buf,
		width_config = width_config,
		win_opts = win_opts,
		padding = padding,
		is_expanded = false,
		list_buffer = win_opts.list_buffer or false,
	}

	-- Cleanup when vsplit closes
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(sidebar_win),
		callback = function()
			M.sidebars[sidebar_win] = nil
		end,
		once = true,
		desc = "Cleanup sidebar on vsplit close",
	})

	-- Setup resize handling
	M._last_editor_width = vim.o.columns
	if not M.resized_autocmd_setup then
		local group = vim.api.nvim_create_augroup("CliIntegrationResize", { clear = true })
		vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
			group = group,
			callback = function()
				M.resize_sidebars()
				if vim.tbl_count(M.sidebars) == 0 then
					pcall(vim.api.nvim_del_augroup_by_name, "CliIntegrationResize")
					M.resized_autocmd_setup = false
				end
			end,
			desc = "Resize sidebar on editor resize",
		})
		M.resized_autocmd_setup = true
	end

	vim.cmd("startinsert")
	return sidebar_win
end

--- Update sidebar geometry (handles fullwidth toggle)
--- @param sidebar_win number The sidebar window handle
--- @param is_expanded boolean Whether to show in fullwidth/float mode
--- @param should_focus boolean|nil Whether to focus the window (default: false)
function M.update_sidebar_geometry(sidebar_win, is_expanded, should_focus)
	local data = M.sidebars[sidebar_win]
	if not data then
		return
	end

	local term_buf = data.terminal_buf
	local win_opts = data.win_opts

	if is_expanded then
		-- Fullwidth mode: hide vsplit, show fullscreen float
		-- Check if we have a vsplit to hide
		if is_valid_win(sidebar_win) then
			local cfg = vim.api.nvim_win_get_config(sidebar_win)
			if cfg.relative == "" then
				-- Hide the vsplit: removes from layout without closing.
				-- Buffer stays loaded because bufhidden=hide is set.
				-- Does NOT trigger WinClosed autocmd.
				pcall(vim.api.nvim_win_hide, sidebar_win)
				-- Clean up sidebar entry since the window is gone from layout
				M.sidebars[sidebar_win] = nil
			end
		end

		-- Create fullwidth float with single border
		local float_opts = {
			relative = "editor",
			width = vim.o.columns,
			height = vim.o.lines - vim.o.cmdheight - 1,
			row = 0,
			col = 0,
			style = "minimal",
			border = "single",
			title = win_opts.title or "",
			title_pos = "center",
		}

		local new_win = vim.api.nvim_open_win(term_buf, true, float_opts)

		if new_win then
			-- Configure float window
			vim.wo[new_win].number = false
			vim.wo[new_win].relativenumber = false
			vim.wo[new_win].signcolumn = "no"
			vim.wo[new_win].spell = false
			vim.wo[new_win].cursorline = false

			-- Update sidebar data for float, preserving hidden vsplit reference
			-- so collapse can find it when toggling back to sidebar mode.
			M.sidebars[new_win] = {
				sidebar_win = new_win,
				terminal_buf = term_buf,
				width_config = data.width_config,
				win_opts = win_opts,
				padding = data.padding,
				is_expanded = true,
				list_buffer = data.list_buffer,
				-- Carry the hidden vsplit handle forward so it survives the entry swap
				hidden_vsplit_win = is_valid_win(sidebar_win) and sidebar_win or nil,
			}

			-- Remove old sidebar entry (vsplit handle kept in hidden_vsplit_win above)
			M.sidebars[sidebar_win] = nil

			-- Resize pty to match the new fullwidth content dimensions
			resize_pty(term_buf, new_win, "single", data.padding or 0)

			-- When the float is closed from outside (e.g. :q), also close the hidden vsplit
			-- so it doesn't remain as a width-0 phantom split.
			vim.api.nvim_create_autocmd("WinClosed", {
				pattern = tostring(new_win),
				callback = function()
					local float_data = M.sidebars[new_win]
					local hidden = float_data and float_data.hidden_vsplit_win
					if hidden and is_valid_win(hidden) then
						pcall(vim.api.nvim_win_close, hidden, true)
					end
					M.sidebars[new_win] = nil
				end,
				once = true,
				desc = "Cleanup fullwidth float and hidden vsplit on close",
			})

			if should_focus then
				vim.api.nvim_set_current_win(new_win)
				vim.schedule(function()
					if is_valid_win(new_win) then
						vim.cmd("startinsert")
					end
				end)
			end
		end
	else
		-- Sidebar mode: close float, restore vsplit
		local hidden_vsplit_win = data.hidden_vsplit_win

		if is_valid_win(sidebar_win) then
			local cfg = vim.api.nvim_win_get_config(sidebar_win)
			if cfg.relative ~= "" then
				-- Clear the sidebar entry BEFORE closing the float so the WinClosed autocmd
				-- sees an empty entry and does NOT close the hidden vsplit we are about to restore.
				M.sidebars[sidebar_win] = nil
				vim.api.nvim_win_close(sidebar_win, true)
			end
		end

		if hidden_vsplit_win and is_valid_win(hidden_vsplit_win) then
			-- Restore the hidden vsplit to its configured width
			local padding = data.padding or 0
			local configured_width = calculate_width(data.width_config)
			local target_width = configured_width - (padding * 2)
			vim.api.nvim_win_set_width(hidden_vsplit_win, target_width)

			-- Resize pty to match the restored sidebar content dimensions
			resize_pty(term_buf, hidden_vsplit_win, "none", data.padding or 0)

			-- Re-register the vsplit as the active sidebar entry
			M.sidebars[hidden_vsplit_win] = {
				sidebar_win = hidden_vsplit_win,
				terminal_buf = term_buf,
				width_config = data.width_config,
				win_opts = win_opts,
				padding = data.padding,
				is_expanded = false,
				list_buffer = data.list_buffer,
			}

			if should_focus then
				vim.api.nvim_set_current_win(hidden_vsplit_win)
				vim.schedule(function()
					if is_valid_win(hidden_vsplit_win) then
						vim.cmd("startinsert")
					end
				end)
			end
		else
			-- No hidden vsplit found (e.g. it was closed externally), create new one
			local vsplit_win = M.create_sidebar_layout(term_buf, win_opts)
			if vsplit_win then
				if should_focus then
					vim.api.nvim_set_current_win(vsplit_win)
					vim.schedule(function()
						if is_valid_win(vsplit_win) then
							vim.cmd("startinsert")
						end
					end)
				end
			end
		end
	end
end

--- Resize all sidebar windows (handles editor resize and fullwidth)
function M.resize_sidebars()
	local editor_resized = vim.o.columns ~= M._last_editor_width
	if editor_resized then
		M._last_editor_width = vim.o.columns
	end

	for sidebar_win, data in pairs(M.sidebars) do
		if is_valid_win(sidebar_win) then
			if data.is_expanded then
				-- Fullwidth mode: resize float to full editor coverage
				pcall(vim.api.nvim_win_set_config, sidebar_win, {
					relative = "editor",
					width = vim.o.columns,
					height = vim.o.lines - vim.o.cmdheight - 1,
					row = 0,
					col = 0,
					style = "minimal",
					border = "single",
				})
				-- Resize pty to match the new fullwidth content dimensions
				resize_pty(data.terminal_buf, sidebar_win, "single", data.padding or 0)
			elseif editor_resized then
				-- Editor was resized: recalculate vsplit width
				local padding = data.padding or 0
				local configured_width = calculate_width(data.width_config)
				local target_width = configured_width - (padding * 2)
				pcall(vim.api.nvim_win_set_width, sidebar_win, target_width)
				-- Resize pty to match the new sidebar content dimensions
				resize_pty(data.terminal_buf, sidebar_win, "none", data.padding or 0)
			end
		else
			-- Cleanup invalid windows
			M.sidebars[sidebar_win] = nil
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

	-- Find current sidebar window for this terminal's buffer
	local current_sidebar_win = nil
	for win, data in pairs(M.sidebars) do
		if data.terminal_buf == terminal.buf then
			current_sidebar_win = win
			break
		end
	end

	if current_sidebar_win and vim.api.nvim_win_is_valid(current_sidebar_win) then
		-- Close the terminal window
		vim.api.nvim_win_close(current_sidebar_win, false)
		terminal.win = nil
		-- M.sidebars cleanup happens via WinClosed autocmd
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
