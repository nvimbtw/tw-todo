-- INFO: Scanning buffer/file lines for tw-todo hash markers

local M = {}

--- Scan lines for hash markers; the comment line above provides the
--- description for recreating purged tasks.
---@param lines string[]
---@return table<string, { description: string?, keyword: string, lnum: integer }>
function M.lines(lines)
    local pat = vim.pesc(require("tw-todo.config").options.hash_prefix)
        .. "(%x%x%x%x%x%x%x)"
    local found = {}
    for i, line in ipairs(lines) do
        local hash = line:match(pat)
        if hash then
            local keyword, desc = (lines[i - 1] or ""):match("(%u[%u%d]+):%s*(.-)%s*$")
            if desc then
                -- strip closers of block-style commentstrings ("*/", "-->")
                desc = desc:gsub("%s*%*/$", ""):gsub("%s*%-%->$", "")
            end
            found[hash] = { description = desc, keyword = keyword or "TODO", lnum = i }
        end
    end
    return found
end

return M
