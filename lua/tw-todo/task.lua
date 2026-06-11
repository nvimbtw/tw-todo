-- INFO: Taskwarrior CLI interface

local M = {}

local function options()
    return require("tw-todo.config").options.taskwarrior
end

-- UDAs linking a task to its comment: twhash holds the hash on the line under
-- the TODO/FIX comment, twfile the file it lives in (relative to the project
-- root). Passed as rc overrides on every invocation so the user's taskrc
-- needs no changes.
local overrides = {
    "rc.confirmation=off",
    "rc.verbose=nothing",
    "rc.uda.twhash.type=string",
    "rc.uda.twhash.label=tw-todo hash",
    "rc.uda.twfile.type=string",
    "rc.uda.twfile.label=tw-todo file",
    "rc.uda.twissue.type=numeric",
    "rc.uda.twissue.label=tw-todo issue",
}

-- Taskwarrior 3's sqlite backend fails fast when two `task` processes touch
-- the database at once, so plugin commands run one at a time through a queue,
-- and a locked database (e.g. rofi mid-action) is retried with backoff.
local pending = {}
local busy = false

local function next_job()
    local job = table.remove(pending, 1)
    busy = job ~= nil
    if job then
        job()
    end
end

local function run(args, on_done)
    table.insert(pending, function()
        local opts = options()
        local cmd = { opts.command }
        vim.list_extend(cmd, overrides)
        vim.list_extend(cmd, args)

        local attempts = 0
        local function exec()
            local ok, err = pcall(vim.system, cmd, { text = true }, function(out)
                vim.schedule(function()
                    if out.code ~= 0 and (out.stderr or ""):find("database is locked") and attempts < 5 then
                        attempts = attempts + 1
                        vim.defer_fn(exec, 150 * attempts)
                        return
                    end
                    if out.code ~= 0 then
                        vim.notify(
                            ("tw-todo: `%s` failed (exit %d): %s")
                                :format(table.concat(cmd, " "), out.code, vim.trim(out.stderr or "")),
                            vim.log.levels.ERROR
                        )
                    elseif on_done then
                        pcall(on_done, out) -- a failing callback must not wedge the queue
                    end
                    next_job()
                end)
            end)
            if not ok then
                vim.notify(
                    ("tw-todo: could not run %s: %s"):format(opts.command, err),
                    vim.log.levels.ERROR
                )
                next_job()
            end
        end
        exec()
    end)
    if not busy then
        next_job()
    end
end

--- Project root directory: the nearest directory above the buffer's file
--- containing one of taskwarrior.root_markers, falling back to the cwd. The
--- walk starts at the file (not the cwd) so opening a parent folder full of
--- projects still resolves each file to its own project.
---@param buf? integer
---@return string
function M.project_root(buf)
    local file = vim.api.nvim_buf_get_name(buf or 0)
    local dir = file ~= "" and vim.fs.dirname(file) or vim.uv.cwd()
    return vim.fs.root(dir, options().root_markers) or vim.uv.cwd()
end

--- Name used for `project:` on created tasks. Resolution order:
--- opts.taskwarrior.project (string or function), the project root name.
---@param buf? integer
---@return string|nil
function M.project_name(buf)
    local opts = options()
    if type(opts.project) == "function" then
        return opts.project(buf)
    end
    if opts.project then
        return opts.project
    end
    return vim.fs.basename(M.project_root(buf))
end

--- Path of the buffer's file relative to the project root (as stored in twfile).
---@param buf? integer
---@return string|nil
function M.buf_relpath(buf)
    local file = vim.api.nvim_buf_get_name(buf or 0)
    if file == "" then
        return nil
    end
    local root = M.project_root(buf)
    local rel = vim.fs.relpath(root, file)
    return rel or file
end

--- Create a task for a comment.
---@param spec { description: string, hash: string, keyword: string, buf?: integer, file?: string, extra?: string[] }
---@param on_done? fun(out: vim.SystemCompleted)
function M.add(spec, on_done)
    local args = { "add", spec.description, "+" .. spec.keyword:lower(), "twhash:" .. spec.hash }
    local project = M.project_name(spec.buf)
    if project and project ~= "" then
        table.insert(args, "project:" .. project)
    end
    local file = spec.file or M.buf_relpath(spec.buf)
    if file then
        table.insert(args, "twfile:" .. file)
    end
    vim.list_extend(args, spec.extra or {})
    run(args, on_done)
end

--- Mark the task linked to a comment hash as done.
---@param hash string
---@param on_done? fun(out: vim.SystemCompleted)
function M.complete(hash, on_done)
    run({ "twhash:" .. hash, "done" }, on_done)
end

--- Mark a task as done by uuid.
---@param uuid string
---@param on_done? fun(out: vim.SystemCompleted)
function M.done(uuid, on_done)
    run({ uuid, "done" }, on_done)
end

--- Bring a completed/deleted task back to pending (its comment still exists).
---@param uuid string
---@param on_done? fun(out: vim.SystemCompleted)
function M.reactivate(uuid, on_done)
    run({ uuid, "modify", "status:pending" }, on_done)
end

--- Store the GitHub issue number mirrored from a comment.
---@param uuid string
---@param issue integer
---@param on_done? fun(out: vim.SystemCompleted)
function M.set_issue(uuid, issue, on_done)
    run({ uuid, "modify", "twissue:" .. issue }, on_done)
end

--- Update the stored file path of a task (its comment moved to another file).
---@param uuid string
---@param file string
---@param on_done? fun(out: vim.SystemCompleted)
function M.set_file(uuid, file, on_done)
    run({ uuid, "modify", "twfile:" .. file }, on_done)
end

--- Export tasks as decoded JSON; `filter` is a list of taskwarrior filter args
--- (e.g. { "twhash:a3f9c12" } or { "status:pending", "project:tw-todo" }).
---@param filter? string[]
---@param on_done fun(tasks: table[])
function M.export(filter, on_done)
    local args = vim.list_extend(vim.deepcopy(filter or {}), { "export" })
    run(args, function(out)
        local ok, tasks = pcall(vim.json.decode, out.stdout)
        if not ok then
            vim.notify("tw-todo: could not parse task export: " .. tasks, vim.log.levels.ERROR)
            return
        end
        on_done(tasks)
    end)
end

return M
