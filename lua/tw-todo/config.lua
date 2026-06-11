local M = {}

M.defaults = {
    keymaps = {
        todo = "<leader>tt",
        fix = "<leader>tf",
        list = "<leader>tl",
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
        enabled = true, -- show task status/urgency/due next to hash lines
        format = nil, -- fun(task: table|nil): [string, string][] -- override the chunks
    },
    github = {
        enabled = false, -- mirror comments as GitHub issues via the gh CLI (push-only)
        command = "gh",
        labels = true, -- label issues with the keyword (todo/fix) and your +tags; labels must exist in the repo
        extra_args = {}, -- passed to `gh issue create`, e.g. { "--assignee", "@me", "--milestone", "v1.0" }
    },
}

M.options = vim.deepcopy(M.defaults)

function M.apply(opts)
    M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
    return M.options
end

return M
