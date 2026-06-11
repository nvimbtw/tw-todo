-- INFO: Inline task status next to hash lines, via extmark virtual text.
-- Deliberately minimal: due dates and tags live in the comment itself, the
-- rest in the hover float; this only encodes severity.

local M = {}

local ns = vim.api.nvim_create_namespace("tw-todo")

vim.api.nvim_set_hl(0, "TwTodoPending", { link = "DiagnosticInfo", default = true })
vim.api.nvim_set_hl(0, "TwTodoDue", { link = "DiagnosticWarn", default = true })
vim.api.nvim_set_hl(0, "TwTodoOverdue", { link = "DiagnosticError", default = true })
vim.api.nvim_set_hl(0, "TwTodoActive", { link = "DiagnosticOk", default = true })
vim.api.nvim_set_hl(0, "TwTodoUntracked", { link = "Comment", default = true })

---@param t table|nil exported task for the hash, nil if none exists
---@return [string, string][] virt_text chunks
local function default_format(t)
    if not t then
        return { { "untracked", "TwTodoUntracked" } }
    end
    if t.status ~= "pending" then
        return { { t.status, "TwTodoUntracked" } }
    end
    local chunks = {}
    if t.start then
        table.insert(chunks, { "▶ ", "TwTodoActive" })
    end
    local hl = "TwTodoPending"
    if t.due then
        local epoch = require("tw-todo.util").utc_epoch(t.due)
        local days = epoch and (epoch - os.time()) / 86400
        local soon = require("tw-todo.config").options.virtual_text.soon_days or 3
        if days and days < 0 then
            hl = "TwTodoOverdue"
        elseif days and days <= soon then
            hl = "TwTodoDue"
        end
    end
    table.insert(chunks, { ("● %.1f"):format(t.urgency or 0), hl })
    return chunks
end

--- Re-render virtual text for every hash line in the buffer. Async.
---@param buf? integer
function M.refresh(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    local opts = require("tw-todo.config").options
    if not (opts.virtual_text.enabled and opts.taskwarrior.enabled) then
        return
    end
    local task = require("tw-todo.task")
    local found = require("tw-todo.scan").lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    if vim.tbl_isempty(found) then
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
        return
    end
    task.export({ "project:" .. task.project_name(buf) }, function(tasks)
        if not vim.api.nvim_buf_is_valid(buf) then
            return
        end
        local by_hash = {}
        for _, t in ipairs(tasks) do
            if t.twhash then
                by_hash[t.twhash] = t
            end
        end
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
        local format = opts.virtual_text.format or default_format
        for hash, info in pairs(found) do
            local chunks = format(by_hash[hash])
            if chunks and #chunks > 0 and info.lnum <= vim.api.nvim_buf_line_count(buf) then
                vim.api.nvim_buf_set_extmark(buf, ns, info.lnum - 1, 0, {
                    virt_text = chunks,
                    virt_text_pos = "eol",
                })
            end
        end
    end)
end

return M
