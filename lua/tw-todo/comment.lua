-- INFO: Building and inserting TODO/FIX comments at the cursor

local M = {}

-- Short unique id (7 hex chars) used later to match the comment to a
-- taskwarrior task, since the description text may be edited.
local function gen_hash(desc)
    return vim.fn.sha256(desc .. vim.loop.hrtime() .. math.random(1e9)):sub(1, 7)
end

-- Attributes that may be passed through to `task add` from the input prompt.
-- A whitelist so prose colons ("see http://x.com") stay in the description.
local attrs = {
    due = true,
    priority = true,
    project = true,
    scheduled = true,
    ["until"] = true,
    wait = true,
    recur = true,
    depends = true,
}

--- Split the typed input into the comment description and taskwarrior
--- arguments: `fix parser due:friday +urgent` -> "fix parser", {"due:friday", "+urgent"}
---@param input string
---@return string description, string[] extra
function M.parse_input(input)
    local desc, extra = {}, {}
    for token in input:gmatch("%S+") do
        local attr = token:match("^(%a+):")
        if token:match("^%+%S+$") or (attr and attrs[attr]) then
            table.insert(extra, token)
        else
            table.insert(desc, token)
        end
    end
    return table.concat(desc, " "), extra
end

--- The hash line plus optional metadata lines, keys padded to one column:
---   tw:   a3f9c12
---   due:  2026-06-20
---   tags: +urgent +backend
---@param indent string
---@param cs string commentstring
---@param hash string
---@param due? string
---@param tags? string[]
---@return string[]
local function block_lines(indent, cs, hash, due, tags)
    local prefix = require("tw-todo.config").options.hash_prefix
    local width = math.max(#prefix, #"tags:") + 1
    local function pad(key)
        return key .. string.rep(" ", width - #key)
    end
    local lines = { indent .. cs:format(pad(prefix) .. hash) }
    if due then
        table.insert(lines, indent .. cs:format(pad("due:") .. due))
    end
    if tags and #tags > 0 then
        table.insert(lines, indent .. cs:format(pad("tags:") .. "+" .. table.concat(tags, " +")))
    end
    return lines
end

---@param buf integer
---@return string
local function commentstring(buf)
    local cs = vim.bo[buf].commentstring
    if cs == nil or cs == "" then
        cs = "// %s"
    end
    return cs
end

--- Rewrite a comment's hash/metadata block from an exported task, so the
--- comment shows canonical values ("due:friday" -> "due:2026-06-12") and
--- stays in step after a sync. No-op when the block already matches.
---@param buf integer
---@param hash string
---@param t table exported task
function M.write_meta(buf, hash, t)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    local entry = require("tw-todo.scan").lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false))[hash]
    if not entry then
        return
    end
    local due = t.due and require("tw-todo.util").local_date(t.due) or nil
    local keyword_tag = entry.keyword:lower()
    local tags = {}
    for _, tag in ipairs(t.tags or {}) do
        if tag ~= keyword_tag then
            table.insert(tags, tag)
        end
    end
    local cur = vim.api.nvim_buf_get_lines(buf, entry.lnum - 1, entry.end_lnum, false)
    local indent = (cur[1] or ""):match("^%s*") or ""
    local new = block_lines(indent, commentstring(buf), hash, due, tags)
    if not vim.deep_equal(cur, new) then
        vim.api.nvim_buf_set_lines(buf, entry.lnum - 1, entry.end_lnum, false, new)
    end
end

---@param keyword string "TODO" | "FIX"
function M.insert(keyword)
    -- Capture buffer/cursor before the float steals focus
    local buf = vim.api.nvim_get_current_buf()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local cur_line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    local indent = cur_line:match("^%s*") or ""
    local cs = commentstring(buf)

    require("tw-todo.ui").input(keyword .. " description:", function(input)
        if not input then
            return
        end
        local opts = require("tw-todo.config").options
        local desc, extra = M.parse_input(input)
        if desc == "" then
            return
        end
        local hash = gen_hash(desc)
        local due, tags = nil, {}
        for _, token in ipairs(extra) do
            local tag = token:match("^%+(%S+)$")
            if tag then
                table.insert(tags, tag)
            else
                due = token:match("^due:(%S+)$") or due
            end
        end
        local lines = { indent .. cs:format(keyword .. ": " .. desc) }
        vim.list_extend(lines, block_lines(indent, cs, hash, due, tags))
        -- Insert above the current line, like a comment annotating the code below
        vim.api.nvim_buf_set_lines(buf, row - 1, row - 1, false, lines)

        if opts.taskwarrior.enabled then
            local task = require("tw-todo.task")
            local spec = { description = desc, hash = hash, keyword = keyword, buf = buf, extra = extra }
            task.add(spec, function()
                vim.notify("tw-todo: task created (" .. hash .. ")", vim.log.levels.INFO)
                if opts.github.enabled then
                    require("tw-todo.github").create(spec)
                end
                -- canonicalize fuzzy dates ("due:friday") to what taskwarrior stored
                task.export({ "twhash:" .. hash }, function(tasks)
                    if tasks[1] then
                        M.write_meta(buf, hash, tasks[1])
                    end
                    if opts.virtual_text.enabled then
                        require("tw-todo.virtual").refresh(buf)
                    end
                end)
            end)
        end
    end)
end

return M
