local M = {}

M.defaults = {
    keymaps = {
        todo = "<leader>tt",
        fix = "<leader>tf",
        list = "<leader>tl",
        hover = "<leader>ti",
        develop = "<leader>tb",
    },
    hash_prefix = "tw:", -- prefix on the hash line under the comment
    taskwarrior = {
        enabled = true, -- create a taskwarrior task when a comment is inserted
        command = "task",
        project = nil, -- string | fun(buf): string; default: project root directory name
        -- The project root is the nearest directory above the buffer's file
        -- containing one of these; `touch .tw-todo` to mark a root explicitly.
        root_markers = { ".tw-todo", ".git", "package.json", "Cargo.toml", "go.mod", "pyproject.toml", "Makefile" },
    },
    sync = {
        on_write = true, -- reconcile comments with taskwarrior after saving a file (async)
    },
    virtual_text = {
        enabled = true, -- show a small status/severity indicator next to hash lines
        soon_days = 3, -- due within this many days renders as TwTodoDue (warn)
        format = nil, -- fun(task: table|nil): [string, string][] -- override the chunks
    },
    merge = {
        enabled = true, -- offer merging a develop branch back into its base when its task completes
        message = "close #%d: %s", -- commit message for the comment-removal commit (issue, description)
        delete_branch = true, -- delete the local develop branch after merging (the remote is never touched)
    },
    github = {
        enabled = false, -- mirror comments as GitHub issues via the gh CLI (push-only)
        command = "gh",
        labels = true, -- label issues with the keyword (todo/fix) and your +tags; labels must exist in the repo
        extra_args = {}, -- passed to `gh issue create`, e.g. { "--assignee", "@me", "--milestone", "v1.0" }
        develop = {
            start_task = true, -- `task start` the task after checking out its develop branch
        },
    },
}

M.options = vim.deepcopy(M.defaults)

function M.apply(opts)
    M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
    return M.options
end

return M
