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

---@param keyword string "TODO" | "FIX"
function M.insert(keyword)
    -- Capture buffer/cursor before the float steals focus
    local buf = vim.api.nvim_get_current_buf()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local cur_line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    local indent = cur_line:match("^%s*") or ""
    local cs = vim.bo[buf].commentstring
    if cs == nil or cs == "" then
        cs = "// %s"
    end

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
        local lines = {
            indent .. cs:format(keyword .. ": " .. desc),
            indent .. cs:format(opts.hash_prefix .. hash),
        }
        -- Insert above the current line, like a comment annotating the code below
        vim.api.nvim_buf_set_lines(buf, row - 1, row - 1, false, lines)

        if opts.taskwarrior.enabled then
            local spec = { description = desc, hash = hash, keyword = keyword, buf = buf, extra = extra }
            require("tw-todo.task").add(spec, function()
                vim.notify("tw-todo: task created (" .. hash .. ")", vim.log.levels.INFO)
                if opts.github.enabled then
                    require("tw-todo.github").create(spec)
                end
                if opts.virtual_text.enabled then
                    require("tw-todo.virtual").refresh(buf)
                end
            end)
        end
    end)
end

return M
