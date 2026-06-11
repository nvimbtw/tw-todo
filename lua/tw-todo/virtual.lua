-- INFO: Inline task status next to hash lines, via extmark virtual text

local M = {}

local ns = vim.api.nvim_create_namespace("tw-todo")

vim.api.nvim_set_hl(0, "TwTodoPending", { link = "DiagnosticInfo", default = true })
vim.api.nvim_set_hl(0, "TwTodoDue", { link = "DiagnosticWarn", default = true })
vim.api.nvim_set_hl(0, "TwTodoActive", { link = "DiagnosticOk", default = true })
vim.api.nvim_set_hl(0, "TwTodoUntracked", { link = "Comment", default = true })

--- taskwarrior timestamps are UTC ("20260630T220000Z"); render the local date.
---@param ts string
---@return string
local function local_date(ts)
    local y, m, d, H, Mi, S = ts:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z$")
    if not y then
        return ts
    end
    -- os.time reads the fields as local time; correct by comparing against the
    -- same instant's UTC field set (isdst left to libc, or DST is off by 1h)
    local guess = os.time({ year = y, month = m, day = d, hour = H, min = Mi, sec = S })
    local utc_fields = os.date("!*t", guess) --[[@as osdate]]
    utc_fields.isdst = nil
    local offset = os.difftime(guess, os.time(utc_fields))
    return os.date("%Y-%m-%d", guess + offset) --[[@as string]]
end

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
        table.insert(chunks, { "▶ tracking ", "TwTodoActive" })
    end
    table.insert(chunks, { ("● %.1f"):format(t.urgency or 0), "TwTodoPending" })
    if t.due then
        table.insert(chunks, { " due " .. local_date(t.due), "TwTodoDue" })
    end
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
