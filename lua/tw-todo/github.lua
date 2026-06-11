-- INFO: Mirror comments as GitHub issues via the gh CLI. Push-only: we
-- create/close/reopen issues from the code side and never poll GitHub.

local M = {}

local function options()
    return require("tw-todo.config").options.github
end

---@param root string
---@param args string[]
---@param on_done? fun(out: vim.SystemCompleted)
---@param on_error? fun(out: vim.SystemCompleted) replaces the default error notification
local function gh(root, args, on_done, on_error)
    local cmd = { options().command }
    vim.list_extend(cmd, args)
    local ok, err = pcall(vim.system, cmd, { text = true, cwd = root }, function(out)
        vim.schedule(function()
            if out.code ~= 0 then
                if on_error then
                    on_error(out)
                else
                    vim.notify(
                        ("tw-todo: `%s` failed (exit %d): %s")
                            :format(table.concat(cmd, " "), out.code, vim.trim(out.stderr or "")),
                        vim.log.levels.ERROR
                    )
                end
            elseif on_done then
                on_done(out)
            end
        end)
    end)
    if not ok then
        vim.notify(
            ("tw-todo: could not run %s: %s"):format(options().command, err),
            vim.log.levels.ERROR
        )
    end
end

local remote_cache = {} ---@type table<string, boolean>

--- Whether the project root has a GitHub origin remote (cached per root).
---@param root string
---@param cb fun(ok: boolean)
local function remote_ok(root, cb)
    if remote_cache[root] ~= nil then
        cb(remote_cache[root])
        return
    end
    vim.system({ "git", "-C", root, "remote", "get-url", "origin" }, { text = true }, function(out)
        vim.schedule(function()
            remote_cache[root] = out.code == 0 and out.stdout:find("github%.com") ~= nil
            cb(remote_cache[root])
        end)
    end)
end

--- Labels for an issue: the keyword (todo/fix) plus any +tags typed in the
--- input prompt.
---@param spec { keyword?: string, extra?: string[] }
---@return string[]
local function issue_labels(spec)
    local labels = {}
    if spec.keyword then
        table.insert(labels, spec.keyword:lower())
    end
    for _, token in ipairs(spec.extra or {}) do
        local tag = token:match("^%+(%S+)$")
        if tag then
            table.insert(labels, tag)
        end
    end
    return labels
end

--- Create an issue mirroring a comment and store its number on the task.
---@param spec { description: string, hash: string, keyword?: string, extra?: string[], buf?: integer, file?: string }
function M.create(spec)
    local task = require("tw-todo.task")
    local opts = options()
    local root = task.project_root(spec.buf)
    remote_ok(root, function(ok)
        if not ok then
            return
        end
        local prefix = require("tw-todo.config").options.hash_prefix
        local file = spec.file or task.buf_relpath(spec.buf) or "?"
        local body = ("Tracked comment `%s%s` in `%s`.\n\n_Managed by tw-todo.nvim — the issue closes when the comment is removed._")
            :format(prefix, spec.hash, file)

        local base = { "issue", "create", "--title", spec.description, "--body", body }
        vim.list_extend(base, opts.extra_args or {})
        local labeled = vim.deepcopy(base)
        local labels = opts.labels and issue_labels(spec) or {}
        for _, label in ipairs(labels) do
            vim.list_extend(labeled, { "--label", label })
        end

        local function on_created(out)
            local issue = out.stdout:match("/issues/(%d+)")
            if not issue then
                vim.notify("tw-todo: could not parse issue number from gh output", vim.log.levels.WARN)
                return
            end
            task.set_issue("twhash:" .. spec.hash, tonumber(issue), function()
                vim.notify(("tw-todo: opened issue #%s (%s)"):format(issue, spec.hash), vim.log.levels.INFO)
            end)
        end

        -- gh rejects labels that don't exist in the repo; fall back to an
        -- unlabeled issue rather than not creating one at all
        gh(root, labeled, on_created, function(out)
            if #labels > 0 then
                vim.notify(
                    ("tw-todo: issue labels rejected (%s), retrying without labels: %s")
                        :format(table.concat(labels, ", "), vim.trim(out.stderr or "")),
                    vim.log.levels.WARN
                )
                gh(root, base, on_created)
            else
                vim.notify(
                    ("tw-todo: `gh issue create` failed (exit %d): %s")
                        :format(out.code, vim.trim(out.stderr or "")),
                    vim.log.levels.ERROR
                )
            end
        end)
    end)
end

---@param root string
---@param issue integer
function M.close(root, issue)
    gh(root, { "issue", "close", tostring(issue) }, function()
        vim.notify("tw-todo: closed issue #" .. issue, vim.log.levels.INFO)
    end)
end

--- Mirror a comment's tags-line edit onto the issue's labels.
---@param root string
---@param issue integer
---@param add string[]
---@param remove string[]
function M.edit_labels(root, issue, add, remove)
    if not options().labels then
        return
    end
    local args = { "issue", "edit", tostring(issue) }
    for _, label in ipairs(add) do
        vim.list_extend(args, { "--add-label", label })
    end
    for _, label in ipairs(remove) do
        vim.list_extend(args, { "--remove-label", label })
    end
    -- like create: labels missing from the repo are not worth an error
    gh(root, args, nil, function(out)
        vim.notify(
            ("tw-todo: issue #%d label update skipped: %s"):format(issue, vim.trim(out.stderr or "")),
            vim.log.levels.WARN
        )
    end)
end

local function git(root, args, on_done)
    require("tw-todo.git").run(root, args, on_done)
end

--- Create and check out the issue-linked branch for a task, after an explicit
--- confirmation. The branch name is computed locally (gh's `<issue>-<slug>`
--- convention) so the prompt shows exactly what will be created.
---
--- gh registers the linked branch remotely (based on the current branch, not
--- the repo default), but the local switch is `git switch -C` at HEAD: unlike
--- gh's --checkout it carries uncommitted changes along — inserting a comment
--- always dirties the tree, so a plain checkout would refuse with "commit or
--- stash your changes". No commits are ever pushed.
---@param t table exported task (needs twissue, description, uuid)
---@param buf? integer
function M.develop(t, buf)
    if not t.twissue then
        vim.notify("tw-todo: no GitHub issue linked to this comment", vim.log.levels.WARN)
        return
    end
    local slug = (t.description or ""):lower():gsub("[^%w]+", "-"):sub(1, 40):gsub("^%-+", ""):gsub("%-+$", "")
    local name = t.twissue .. (slug ~= "" and "-" .. slug or "")
    local choice = vim.fn.confirm(
        ('tw-todo: this will create and checkout branch "%s". Continue?'):format(name),
        "&Yes\n&No",
        2
    )
    if choice ~= 1 then
        return
    end
    local task = require("tw-todo.task")
    local root = task.project_root(buf)
    git(root, { "branch", "--show-current" }, function(out)
        local base = vim.trim(out.stdout or "")
        local args = { "issue", "develop", tostring(t.twissue), "--name", name }
        if base ~= "" then
            vim.list_extend(args, { "--base", base })
        end
        gh(root, args, function()
            git(root, { "switch", "-C", name }, function()
                -- track the remote branch gh created, so a later plain
                -- `git push` does the right thing (explicit refspec: a bare
                -- `fetch origin <name>` only updates FETCH_HEAD)
                git(root, { "fetch", "origin", ("+refs/heads/%s:refs/remotes/origin/%s"):format(name, name) }, function()
                    git(root, { "branch", "-u", "origin/" .. name, name })
                end)
                -- remember the branch and its base for the merge-back
                if t.uuid then
                    task.set_branch(t.uuid, name, base)
                end
                vim.notify(
                    ("tw-todo: on branch %s (issue #%d)"):format(name, t.twissue),
                    vim.log.levels.INFO
                )
                if options().develop.start_task and t.uuid then
                    task.start(t.uuid, function()
                        require("tw-todo.virtual").refresh(buf)
                    end)
                end
            end)
        end)
    end)
end

--- Develop the comment block under the cursor.
function M.develop_at_cursor()
    local buf = vim.api.nvim_get_current_buf()
    local hash = require("tw-todo.scan").at_cursor(buf)
    if not hash then
        vim.notify("tw-todo: no tracked comment under cursor", vim.log.levels.WARN)
        return
    end
    require("tw-todo.task").export({ "twhash:" .. hash }, function(tasks)
        if not tasks[1] then
            vim.notify("tw-todo: no task found for " .. hash, vim.log.levels.WARN)
            return
        end
        M.develop(tasks[1], buf)
    end)
end

---@param root string
---@param issue integer
function M.reopen(root, issue)
    gh(root, { "issue", "reopen", tostring(issue) }, function()
        vim.notify("tw-todo: reopened issue #" .. issue, vim.log.levels.INFO)
    end)
end

return M
