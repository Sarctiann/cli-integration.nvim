local M = {}

--- @class Cli-Integration.Session
--- @field id string The session identifier (e.g., filename or sessionId)
--- @field modified string|nil ISO date or timestamp (e.g., "2024-03-09T10:00:00Z")
--- @field display string|nil Optional display text for the picker
--- @field workspace string|nil Optional workspace root for filtering
--- @field file_path string|nil Optional absolute path to the session file (often used in delete_cmd)

--- @class Cli-Integration.ManageSessionsOpts
--- @field name string Name of the CLI (e.g., "Gemini")
--- @field base_dir string|nil Path where sessions are stored (not needed if get_sessions is used)
--- @field pattern string|nil Glob pattern for session files (e.g., "*.json", default: "*")
--- @field get_sessions (fun(): Cli-Integration.Session[])|nil Function that returns all sessions (if provided, base_dir is ignored)
--- @field parse_session (fun(file_path: string): Cli-Integration.Session|nil)|nil Logic to extract session data from a file
--- @field resume_cmd string Command template for resuming (e.g., "CLIIntegration open_root Gemini --resume %s")
--- @field delete_cmd fun(session: Cli-Integration.Session) Logic to delete a session (receives the session object)
--- @field show_all boolean|nil Initial state of the "show all" toggle (default: false)

--- Internal helper to get current git root or cwd
--- @return string
function M.get_current_workspace()
	local git_root_list = vim.fn.systemlist("git rev-parse --show-toplevel")
	return (vim.v.shell_error == 0 and git_root_list[1]) or vim.fn.getcwd()
end

--- Helper to create a start_with_text function that wraps visual selection
--- or returns the formatted current path if no selection is present.
--- @param prefix string|nil Prefix for visual selection (default: "Explain this code:\n```\n")
--- @param suffix string|nil Suffix for visual selection (default: "\n```\n")
--- @return fun(visual_text: string|nil, integration: Cli-Integration.Integration|nil): string
function M.insert_current_path_or_explain_selection(prefix, suffix)
	prefix = prefix or "Explain this code:\n```\n"
	suffix = suffix or "\n```\n"

	return function(visual_text, integration)
		if visual_text then
			return prefix .. visual_text .. suffix
		end

		-- Look up terminal data directly by integration name (reliable regardless of current focus)
		local terminal = require("cli-integration.terminal")
		local term_data = integration and integration.name and terminal.terminals[integration.name]

		local relative_path
		if term_data and term_data.current_file then
			relative_path = term_data.current_file
		else
			-- Fallback: terminal not found, use current buffer path
			local current_file_abs = vim.fn.expand("%:p")
			local workspace = M.get_current_workspace()
			relative_path = vim.fs.relpath(workspace, current_file_abs)
				or vim.fn.fnamemodify(current_file_abs, ":.")
		end

		-- Format if integration provides it
		if integration and integration.format_paths then
			return integration.format_paths(relative_path)
		end
		return relative_path
	end
end

--- Generalized session manager engine
--- @param opts Cli-Integration.ManageSessionsOpts Configuration for the session manager
function M.manage_sessions(opts)
	--- @type Cli-Integration.Session[]
	local sessions = {}

	if opts.get_sessions then
		sessions = opts.get_sessions() or {}
	elseif opts.base_dir and opts.parse_session then
		local session_files = vim.fn.glob(opts.base_dir .. "/" .. (opts.pattern or "*"), false, true)
		for _, file_path in ipairs(session_files) do
			local session = opts.parse_session(file_path)
			if session then
				table.insert(sessions, session)
			end
		end
	end

	-- Safety check: ensure sessions is a table
	if type(sessions) ~= "table" then
		sessions = {}
	end

	if #sessions == 0 then
		vim.notify("No " .. opts.name .. " sessions found", vim.log.levels.INFO)
		return
	end

	local current_workspace = M.get_current_workspace()
	local filtered_sessions = {}
	if opts.show_all then
		filtered_sessions = sessions
	else
		for _, s in ipairs(sessions) do
			if s.workspace == current_workspace then
				table.insert(filtered_sessions, s)
			end
		end
	end

	-- If no sessions for workspace, toggle to all
	if #filtered_sessions == 0 and not opts.show_all then
		vim.notify("No sessions for current workspace, showing all", vim.log.levels.INFO)
		opts.show_all = true
		return M.manage_sessions(opts)
	end

	-- Sort by most recent
	table.sort(filtered_sessions, function(a, b)
		return (a.modified or "") > (b.modified or "")
	end)

	local display_items = { ">>> 🔄 Toggle All Sessions", ">>> ➕ Create New Session" }
	for _, s in ipairs(filtered_sessions) do
		table.insert(display_items, s.display or string.format("[%s] %s", s.modified or "Unknown", s.id))
	end

	vim.schedule(function()
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-j><C-j>", true, false, true), "n", false)
	end)

	vim.ui.select(display_items, {
		prompt = opts.name .. " Sessions " .. (opts.show_all and "[All]" or "[Project]") .. " (Esc: Cancel)",
	}, function(choice, idx)
		if not choice or not idx then
			return
		end
		if idx == 1 then
			opts.show_all = not opts.show_all
			return M.manage_sessions(opts)
		end
		if idx == 2 then
			local cmd = opts.resume_cmd:format(""):gsub("%s%-%-resume%s$", ""):gsub("%s%s+", " ")
			return vim.cmd(cmd)
		end

		local session = filtered_sessions[idx - 2]
		vim.ui.select({ "Resume", "Delete", "Go Back" }, {
			prompt = "Action for session: " .. session.id,
		}, function(action)
			if action == "Resume" then
				vim.cmd(opts.resume_cmd:format(session.id))
				-- Focus terminal
				vim.defer_fn(function()
					for _, win in ipairs(vim.api.nvim_list_wins()) do
						local buf = vim.api.nvim_win_get_buf(win)
						if vim.api.nvim_get_option_value("buftype", { buf = buf }) == "terminal" then
							vim.api.nvim_set_current_win(win)
							vim.cmd("startinsert")
							break
						end
					end
				end, 100)
			elseif action == "Delete" then
				vim.ui.select({ "Yes", "No" }, {
					prompt = "⚠️  Delete session " .. session.id .. "?",
				}, function(confirm)
					if confirm == "Yes" then
						opts.delete_cmd(session)
						vim.schedule(function()
							M.manage_sessions(opts)
						end)
					else
						vim.schedule(function()
							M.manage_sessions(opts)
						end)
					end
				end)
			elseif action == "Go Back" then
				vim.schedule(function()
					M.manage_sessions(opts)
				end)
			end
		end)
	end)
end

return M
