-- INFO: Reconcile TODO/FIX comments with taskwarrior. The comment in the code
-- is the source of truth:
--   comment exists, task completed/deleted elsewhere -> task back to pending
--   comment exists, task purged                      -> task recreated
--   comment gone, task pending                       -> task marked done
--   comment moved to another file                    -> twfile updated

local M = {}

local task = require("tw-todo.task")
local scan_lines = require("tw-todo.scan").lines

--- Reconcile one file's comments against the project's tasks.
---@param root string project root (for GitHub issue mirroring)
---@param file string path relative to the project root
---@param found table scan_lines() result for that file
---@param tasks table[] exported tasks for the project
---@return table counts of actions taken
local function reconcile(root, file, found, tasks, buf)
    local gh_enabled = require("tw-todo.config").options.github.enabled
    local github = gh_enabled and require("tw-todo.github") or nil
    local counts = { completed = 0, reactivated = 0, recreated = 0, moved = 0 }
    local by_hash = {}
    for _, t in ipairs(tasks) do
        if t.twhash then
            by_hash[t.twhash] = t
        end
    end

    -- comment gone from the file it was created in -> done
    for _, t in ipairs(tasks) do
        if t.twfile == file and t.status == "pending" and not found[t.twhash] then
            task.done(t.uuid)
            if github and t.twissue then
                github.close(root, t.twissue)
            end
            counts.completed = counts.completed + 1
        end
    end

    -- comment present -> make sure a pending task exists
    for hash, info in pairs(found) do
        local t = by_hash[hash]
        if not t then
            if info.description then
                local spec = {
                    description = info.description,
                    hash = hash,
                    keyword = info.keyword,
                    buf = buf,
                    file = file,
                }
                task.add(spec, github and function()
                    github.create(spec)
                end or nil)
                counts.recreated = counts.recreated + 1
            end
        elseif t.status ~= "pending" then
            task.reactivate(t.uuid)
            if github and t.twissue then
                github.reopen(root, t.twissue)
            end
            counts.reactivated = counts.reactivated + 1
        elseif t.twfile ~= file then
            task.set_file(t.uuid, file)
            counts.moved = counts.moved + 1
        end
    end

    return counts
end

local function notify(counts)
    local parts = {}
    for action, n in pairs(counts) do
        if n > 0 then
            table.insert(parts, n .. " " .. action)
        end
    end
    if #parts > 0 then
        vim.notify("tw-todo sync: " .. table.concat(parts, ", "), vim.log.levels.INFO)
    end
end

--- Sync a single buffer (used on write). Fully async.
---@param buf? integer
function M.sync_buffer(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    local file = task.buf_relpath(buf)
    if not file then
        return
    end
    local found = scan_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    local root = task.project_root(buf)
    task.export({ "project:" .. task.project_name(buf) }, function(tasks)
        notify(reconcile(root, file, found, tasks, buf))
        require("tw-todo.virtual").refresh(buf)
    end)
end

--- Sync the whole project: every file referenced by a task is re-read from
--- disk; files that vanished have their pending tasks completed.
function M.sync_project()
    local buf = vim.api.nvim_get_current_buf()
    local root = task.project_root(buf)
    task.export({ "project:" .. task.project_name(buf) }, function(tasks)
        local files = {}
        for _, t in ipairs(tasks) do
            if t.twfile then
                files[t.twfile] = true
            end
        end
        local totals = { completed = 0, reactivated = 0, recreated = 0, moved = 0 }
        for file in pairs(files) do
            local ok, file_lines = pcall(vim.fn.readfile, vim.fs.joinpath(root, file))
            local found = ok and scan_lines(file_lines) or {}
            for action, n in pairs(reconcile(root, file, found, tasks, buf)) do
                totals[action] = totals[action] + n
            end
        end
        notify(totals)
    end)
end

return M
