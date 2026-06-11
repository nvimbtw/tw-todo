-- INFO: Reconcile TODO/FIX comments with taskwarrior. The comment in the code
-- is the source of truth:
--   comment exists, task completed/deleted elsewhere -> task back to pending
--   comment exists, task purged                      -> task recreated
--   comment gone, task pending                       -> task marked done
--   comment moved to another file                    -> twfile updated

local M = {}

local task = require("tw-todo.task")
local scan_lines = require("tw-todo.scan").lines

--- Difference between a comment's due:/tags: lines and the task. The comment
--- wins: a missing due line clears the date; a tags line (even empty) is the
--- full set of user tags. A comment without a tags line expresses no opinion,
--- so tags set via the CLI on old-format comments survive.
---@param info table scan entry
---@param t table exported task
---@return { due?: string|false, add: string[], remove: string[] }|nil
local function meta_diff(info, t)
    local changes = { add = {}, remove = {} }
    local dirty = false
    local task_due = t.due and require("tw-todo.util").local_date(t.due) or nil
    if info.due ~= task_due then
        -- fuzzy strings ("friday") mismatch too; the modify resolves them and
        -- write_meta then rewrites the comment with the canonical date
        changes.due = info.due or false
        dirty = true
    end
    if info.tags then
        local want, have = {}, {}
        for _, tag in ipairs(info.tags) do
            want[tag] = true
        end
        local keyword_tag = info.keyword:lower()
        for _, tag in ipairs(t.tags or {}) do
            if tag ~= keyword_tag then
                have[tag] = true
            end
        end
        for tag in pairs(want) do
            if not have[tag] then
                table.insert(changes.add, tag)
                dirty = true
            end
        end
        for tag in pairs(have) do
            if not want[tag] then
                table.insert(changes.remove, tag)
                dirty = true
            end
        end
    end
    return dirty and changes or nil
end

--- Reconcile one file's comments against the project's tasks.
---@param root string project root (for GitHub issue mirroring)
---@param file string path relative to the project root
---@param found table scan_lines() result for that file
---@param tasks table[] exported tasks for the project
---@return table counts of actions taken
local function reconcile(root, file, found, tasks, buf)
    local gh_enabled = require("tw-todo.config").options.github.enabled
    local github = gh_enabled and require("tw-todo.github") or nil
    local counts = { completed = 0, reactivated = 0, recreated = 0, moved = 0, updated = 0 }
    local by_hash = {}
    for _, t in ipairs(tasks) do
        if t.twhash then
            by_hash[t.twhash] = t
        end
    end

    -- comment gone from the file it was created in -> done
    local completed = {}
    for _, t in ipairs(tasks) do
        if t.twfile == file and t.status == "pending" and not found[t.twhash] then
            task.done(t.uuid)
            if github and t.twissue then
                github.close(root, t.twissue)
            end
            table.insert(completed, t)
            counts.completed = counts.completed + 1
        end
    end

    -- comment present -> make sure a pending task exists
    for hash, info in pairs(found) do
        local t = by_hash[hash]
        if not t then
            if info.description then
                -- the comment's due:/tags: lines restore those attributes
                local extra = {}
                if info.due then
                    table.insert(extra, "due:" .. info.due)
                end
                for _, tag in ipairs(info.tags or {}) do
                    table.insert(extra, "+" .. tag)
                end
                local spec = {
                    description = info.description,
                    hash = hash,
                    keyword = info.keyword,
                    buf = buf,
                    file = file,
                    extra = extra,
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
        else
            local changes = meta_diff(info, t)
            if changes then
                -- only rewrite comments in a live buffer for this file, never
                -- files read from disk during a project sync
                local live = buf
                    and vim.api.nvim_buf_is_valid(buf)
                    and task.buf_relpath(buf) == file
                task.set_meta(t.uuid, changes, live and function()
                    task.export({ "twhash:" .. hash }, function(ts)
                        if ts[1] then
                            require("tw-todo.comment").write_meta(buf, hash, ts[1])
                        end
                    end)
                end or nil)
                if github and t.twissue and (#changes.add > 0 or #changes.remove > 0) then
                    github.edit_labels(root, t.twissue, changes.add, changes.remove)
                end
                counts.updated = counts.updated + 1
            end
        end
    end

    -- a completed task with a recorded develop branch means the work is done:
    -- offer the merge back into its base. Only from live editing, never from
    -- a bulk project scan.
    if #completed > 0 and require("tw-todo.config").options.merge.enabled then
        local live = buf and vim.api.nvim_buf_is_valid(buf) and task.buf_relpath(buf) == file
        if live then
            require("tw-todo.git").offer_merge(root, completed)
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
        local totals = { completed = 0, reactivated = 0, recreated = 0, moved = 0, updated = 0 }
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
