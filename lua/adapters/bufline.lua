local M = {}

--- Remove the bufferline offset entry for a given term_buf.
--- @param term_buf number
function M.remove_offset(term_buf)
	local ok, bc = pcall(require, "bufferline.config")
	if not ok then
		return
	end

	local cfg = bc.get()
	if not cfg or not cfg.options or not cfg.options.offsets then
		return
	end

	for i, offset in ipairs(cfg.options.offsets) do
		if offset._cli_integration_buf == term_buf then
			table.remove(cfg.options.offsets, i)
			vim.schedule(function()
				vim.cmd("redrawtabline")
			end)
			return
		end
	end
end

--- Inject a bufferline offset for the sidebar vsplit, so bufferline does not
--- draw over the integration window. Best-effort: no-op if bufferline is absent.
--- @param term_buf number
--- @param title string
function M.inject_offset(term_buf, title)
	local ok, bc = pcall(require, "bufferline.config")
	if not ok then
		return
	end

	local cfg = bc.get()
	if not cfg or not cfg.options then
		return
	end

	cfg.options.offsets = cfg.options.offsets or {}

	-- Remove any stale entry for the same buffer before adding a new one
	M.remove_offset(term_buf)

	table.insert(cfg.options.offsets, {
		filetype = "cli-integration",
		text = title,
		highlight = "NormalSB",
		separator = true,
		_cli_integration_buf = term_buf,
	})
	vim.schedule(function()
		vim.cmd("redrawtabline")
	end)
end

return M
