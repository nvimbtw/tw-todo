-- INFO: Scanning buffer/file lines for tw-todo hash markers and the optional
-- metadata lines (due:/tags:) underneath them

local M = {}

-- strip closers of block-style commentstrings ("*/", "-->")
local function strip_closers(s)
    return s:gsub("%s*%*/$", ""):gsub("%s*%-%->$", "")
end

--- Scan lines for hash markers; the comment line above provides the
--- description for recreating purged tasks, the lines below optional
--- metadata (`due:  2026-06-20`, `tags: +urgent +backend`).
---@param lines string[]
---@return table<string, { description: string?, keyword: string, lnum: integer, end_lnum: integer, due: string?, tags: string[]? }>
function M.lines(lines)
    local pat = vim.pesc(require("tw-todo.config").options.hash_prefix)
        .. "%s*(%x%x%x%x%x%x%x)"
    local found = {}
    for i, line in ipairs(lines) do
        local hash = line:match(pat)
        if hash then
            local keyword, desc = (lines[i - 1] or ""):match("(%u[%u%d]+):%s*(.-)%s*$")
            if desc then
                desc = strip_closers(desc)
            end
            local entry = { description = desc, keyword = keyword or "TODO", lnum = i, end_lnum = i }
            local j = i + 1
            while lines[j] do
                local due = lines[j]:match("%f[%a]due:%s*(%S+)")
                local tag_str = lines[j]:match("%f[%a]tags:%s*(.-)%s*$")
                if due and not entry.due then
                    entry.due = strip_closers(due)
                elseif tag_str and not entry.tags then
                    entry.tags = {}
                    for tag in strip_closers(tag_str):gmatch("%+(%S+)") do
                        table.insert(entry.tags, tag)
                    end
                else
                    break
                end
                entry.end_lnum = j
                j = j + 1
            end
            found[hash] = entry
        end
    end
    return found
end

--- The comment block under the cursor (keyword line, hash line or any
--- metadata line), if the cursor is on one.
---@param buf? integer
---@return string? hash, table? entry
function M.at_cursor(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    local found = M.lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    local row = vim.api.nvim_win_get_cursor(0)[1]
    for hash, entry in pairs(found) do
        if row >= entry.lnum - 1 and row <= entry.end_lnum then
            return hash, entry
        end
    end
    return nil, nil
end

return M
