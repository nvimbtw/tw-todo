-- INFO: Local git operations: develop-branch plumbing and merge-back of a
-- finished develop branch into its recorded base. Commit-only: nothing here
-- ever pushes.

local M = {}

---@param root string
---@param args string[]
---@param on_done? fun(out: vim.SystemCompleted)
---@param on_error? fun(out: vim.SystemCompleted) replaces the default error notification
function M.run(root, args, on_done, on_error)
    local cmd = vim.list_extend({ "git", "-C", root }, args)
    vim.system(cmd, { text = true }, function(out)
        vim.schedule(function()
            if out.code ~= 0 then
                if on_error then
                    on_error(out)
                else
                    -- e.g. merge conflicts report on stdout, not stderr
                    local detail = vim.trim(out.stderr or "")
                    if detail == "" then
                        detail = vim.trim(out.stdout or "")
                    end
                    vim.notify(
                        ("tw-todo: `%s` failed: %s"):format(table.concat(cmd, " "), detail),
                        vim.log.levels.ERROR
                    )
                end
            elseif on_done then
                on_done(out)
            end
        end)
    end)
end

local function options()
    return require("tw-todo.config").options.merge
end

--- Commit message for the comment-removal commit: subject for the merged
--- task, one closing line per co-completed task so GitHub closes their
--- issues too.
---@param t table
---@param co_completed table[]
---@return string subject, string|nil body
local function commit_message(t, co_completed)
    local subject = t.twissue and options().message:format(t.twissue, t.description or "")
        or ("done: %s"):format(t.description or "")
    local body = {}
    for _, other in ipairs(co_completed or {}) do
        if other.twissue then
            table.insert(body, ("closes #%d: %s"):format(other.twissue, other.description or ""))
        else
            table.insert(body, ("done: %s"):format(other.description or ""))
        end
    end
    return subject, #body > 0 and table.concat(body, "\n") or nil
end

--- Merge a finished develop branch back into its recorded base:
--- commit the comment-removal (only the comment's file may be dirty),
--- switch to the base, `merge --no-ff`, delete the local branch, and clear
--- the task's twbranch/twbase so it no longer shows up in :TwMerge.
---@param root string
---@param t table exported task (twbranch, twbase, twfile, twissue?, description, uuid)
---@param co_completed? table[] other tasks completed in the same sync pass
function M.merge_back(root, t, co_completed)
    if not (t.twbranch and t.twbase) then
        vim.notify("tw-todo: task has no recorded develop branch/base", vim.log.levels.WARN)
        return
    end
    M.run(root, { "branch", "--show-current" }, function(out)
        if vim.trim(out.stdout or "") ~= t.twbranch then
            vim.notify(
                ("tw-todo: branch %s ready to merge into %s — switch to it and run :TwMerge")
                    :format(t.twbranch, t.twbase),
                vim.log.levels.INFO
            )
            return
        end
        local choice = vim.fn.confirm(
            ('tw-todo: task done — merge "%s" into "%s"?'):format(t.twbranch, t.twbase),
            "&Yes\n&No",
            2
        )
        if choice ~= 1 then
            vim.notify("tw-todo: skipped — run :TwMerge when ready", vim.log.levels.INFO)
            return
        end
        M.run(root, { "status", "--porcelain" }, function(status)
            local dirty = {}
            for line in (status.stdout or ""):gmatch("[^\n]+") do
                -- untracked files don't block a branch switch; ignore them
                if not line:match("^%?%?") then
                    table.insert(dirty, line:sub(4):match("^(.-)%s*$"))
                end
            end
            local function switch_and_merge()
                M.run(root, { "switch", t.twbase }, function()
                    M.run(root, { "merge", "--no-ff", "--no-edit", t.twbranch }, function()
                        local function finish()
                            require("tw-todo.task").set_branch(t.uuid, nil, nil)
                            vim.cmd("checktime")
                            vim.notify(
                                ("tw-todo: merged %s into %s"):format(t.twbranch, t.twbase),
                                vim.log.levels.INFO
                            )
                        end
                        if options().delete_branch then
                            -- -D, not -d: the branch tracks the remote stub gh
                            -- created and is "ahead" of it (we never push), so
                            -- git refuses -d even though we just merged it.
                            -- The merge already happened, so finish (clear the
                            -- task's twbranch/twbase) even if deletion fails.
                            M.run(root, { "branch", "-D", t.twbranch }, finish, function(out)
                                vim.notify(
                                    ("tw-todo: could not delete branch %s: %s")
                                        :format(t.twbranch, vim.trim(out.stderr or "")),
                                    vim.log.levels.WARN
                                )
                                finish()
                            end)
                        else
                            finish()
                        end
                    end)
                end)
            end
            if #dirty == 0 then
                switch_and_merge()
            elseif #dirty == 1 and dirty[1] == t.twfile then
                local subject, body = commit_message(t, co_completed or {})
                local args = { "commit", "-m", subject }
                if body then
                    vim.list_extend(args, { "-m", body })
                end
                M.run(root, { "add", "--", t.twfile }, function()
                    M.run(root, args, switch_and_merge)
                end)
            else
                vim.notify(
                    ("tw-todo: not merging %s — uncommitted changes besides %s; commit them, then :TwMerge")
                        :format(t.twbranch, t.twfile),
                    vim.log.levels.WARN
                )
            end
        end)
    end)
end

--- Offer the merge for a sync pass that completed tasks: at most one branch
--- can match the checked-out branch; others with a branch get a hint.
---@param root string
---@param completed table[] tasks completed in this pass
function M.offer_merge(root, completed)
    M.run(root, { "branch", "--show-current" }, function(out)
        local current = vim.trim(out.stdout or "")
        local match, rest = nil, {}
        for _, t in ipairs(completed) do
            if t.twbranch == current and not match then
                match = t
            else
                table.insert(rest, t)
            end
        end
        for _, t in ipairs(rest) do
            if t.twbranch and t.twbranch ~= "" then
                vim.notify(
                    ("tw-todo: branch %s ready to merge into %s — :TwMerge"):format(t.twbranch, t.twbase or "?"),
                    vim.log.levels.INFO
                )
            end
        end
        if match then
            M.merge_back(root, match, rest)
        end
    end)
end

--- Pick a finished-but-unmerged develop branch and merge it.
function M.merge_picker()
    local task = require("tw-todo.task")
    local buf = vim.api.nvim_get_current_buf()
    local root = task.project_root(buf)
    local filter = { "status:completed", "twbranch.any:", "project:" .. task.project_name(buf) }
    task.export(filter, function(tasks)
        if #tasks == 0 then
            vim.notify("tw-todo: no finished develop branches to merge", vim.log.levels.INFO)
            return
        end
        vim.ui.select(tasks, {
            prompt = "Merge develop branch:",
            format_item = function(t)
                return ("%s → %s  (%s)"):format(t.twbranch, t.twbase or "?", t.description or "")
            end,
        }, function(t)
            if t then
                M.merge_back(root, t, {})
            end
        end)
    end)
end

return M
