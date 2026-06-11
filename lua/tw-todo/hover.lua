-- INFO: K-style hover float with the full task details for the comment block
-- under the cursor (everything that is not in the comment or virtual text)

local M = {}

local function local_datetime(ts)
    local epoch = require("tw-todo.util").utc_epoch(ts)
    if not epoch then
        return ts
    end
    return os.date("%Y-%m-%d %H:%M", epoch) --[[@as string]]
end

---@param hash string
---@param t table|nil exported task
---@return string[] markdown lines
local function render(hash, t)
    if not t then
        return { ("**untracked** — no taskwarrior task for `%s`"):format(hash) }
    end
    local lines = { ("**%s**"):format(t.description or "?"), "" }
    local function row(key, value)
        if value ~= nil and value ~= "" then
            table.insert(lines, ("- %s: %s"):format(key, value))
        end
    end
    row("status", t.status)
    row("urgency", t.urgency and ("%.1f"):format(t.urgency))
    row("priority", t.priority)
    row("project", t.project)
    row("tags", t.tags and #t.tags > 0 and table.concat(t.tags, ", ") or nil)
    for _, field in ipairs({ "due", "scheduled", "wait", "until" }) do
        row(field, t[field] and local_datetime(t[field]))
    end
    row("recur", t.recur)
    row("depends", type(t.depends) == "table" and table.concat(t.depends, ", ") or t.depends)
    row("tracking since", t.start and local_datetime(t.start))
    row("created", t.entry and local_datetime(t.entry))
    row("issue", t.twissue and ("#" .. t.twissue))
    if t.annotations and #t.annotations > 0 then
        table.insert(lines, "")
        table.insert(lines, "**annotations**")
        for _, a in ipairs(t.annotations) do
            table.insert(lines, ("- %s: %s"):format(local_datetime(a.entry or ""), a.description or ""))
        end
    end
    return lines
end

--- Show task details for the comment under the cursor in a floating window.
function M.show()
    local buf = vim.api.nvim_get_current_buf()
    local hash = require("tw-todo.scan").at_cursor(buf)
    if not hash then
        vim.notify("tw-todo: no tracked comment under cursor", vim.log.levels.WARN)
        return
    end
    require("tw-todo.task").export({ "twhash:" .. hash }, function(tasks)
        vim.lsp.util.open_floating_preview(render(hash, tasks[1]), "markdown", {
            border = "rounded",
            focus_id = "tw-todo-hover",
            max_width = 70,
        })
    end)
end

return M
