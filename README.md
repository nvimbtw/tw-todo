# tw-todo.nvim

Structured TODO/FIX comments that live in your code and stay in lockstep with
[taskwarrior](https://taskwarrior.org/) — and optionally with GitHub issues.

Hitting a keybind opens a floating input; the description you type is inserted
above the cursor line as a comment, using the buffer's `commentstring`, together
with a unique hash linking the comment to a taskwarrior task:

```lua
-- TODO: fix the race in scheduler
-- tw:a3f9c12
```

## Setup

```lua
require("tw-todo").setup({
    keymaps = {
        todo = "<leader>tt", -- set any of these to false to disable the mapping
        fix = "<leader>tf",
        list = "<leader>tl", -- task picker
    },
    hash_prefix = "tw:", -- prefix on the hash line
    taskwarrior = {
        enabled = true, -- create a taskwarrior task when a comment is inserted
        command = "task",
        project = nil, -- string | fun(buf): string; default: project root directory name
        -- The project root is found by walking UP from the buffer's file to the
        -- nearest directory containing one of these markers — so it works even
        -- when nvim was opened in a parent folder full of projects. For a
        -- project with no marker, `touch .tw-todo` in its root.
        root_markers = { ".tw-todo", ".git", "package.json", "Cargo.toml", "go.mod", "pyproject.toml", "Makefile" },
    },
    sync = {
        on_write = true, -- reconcile comments with taskwarrior after saving a file (async)
    },
    virtual_text = {
        enabled = true, -- show task status/urgency/due next to hash lines
        format = nil, -- fun(task|nil): chunks — override the rendering
    },
    github = {
        enabled = false, -- mirror comments as GitHub issues via the gh CLI
        command = "gh",
        labels = true, -- label issues with the keyword (todo/fix) and your +tags
        extra_args = {}, -- passed to `gh issue create`, e.g. { "--assignee", "@me", "--milestone", "v1.0" }
    },
})
```

Created tasks get the description you typed, a `+todo`/`+fix` tag, a `project:`
from the root directory name, and UDAs: `twhash` (the comment's hash — the
stable link between code and task), `twfile` (the file the comment lives in,
relative to the project root) and `twissue` (mirrored GitHub issue number).
The UDAs are passed as `rc.` overrides on every invocation, so no `.taskrc`
changes are needed.

The input understands taskwarrior syntax — everything except the plain text is
passed through to `task add` and kept out of the comment:

```
fix the race in scheduler due:friday priority:H +concurrency
```

(Recognized: `+tag` and `due: priority: project: scheduled: until: wait:
recur: depends:`. Note: these extras are restored from taskwarrior, not the
comment, so they are lost if the task is purged and recreated.)

## Sync

The comment in the code is the source of truth. On every save (async, never
blocks) — or on demand with `:TwSync` for the whole project — each comment is
reconciled with taskwarrior:

| code | taskwarrior | result |
| --- | --- | --- |
| comment exists | completed or deleted elsewhere (e.g. rofi) | back to `pending` |
| comment exists | purged / missing | task recreated from the comment text |
| comment removed | pending | marked `done` |
| comment moved to another file | pending | `twfile` updated |

## Picker

`:TwList` (default `<leader>tl`) lists the project's pending tasks sorted by
taskwarrior **urgency** and jumps to the comment on selection.

With [tv.nvim](https://github.com/alexpasmantier/tv.nvim) installed it opens a
[television](https://github.com/alexpasmantier/television) channel (the cable
definition is auto-installed to `~/.config/television/cable/tw-todo.toml` on
first use, and also works standalone: `tv tw-todo` from a project directory).
Without tv.nvim it falls back to `vim.ui.select`.

## Virtual text

Each hash line shows its task's live state after reads, saves, and inserts:
`● 8.2` (urgency, `TwTodoPending`), `due 2026-07-01` (`TwTodoDue`),
`▶ tracking` when the task is active (`TwTodoActive`), the status for
non-pending tasks, or `untracked` (`TwTodoUntracked`) for hashes taskwarrior
doesn't know. Override the highlight groups or pass `virtual_text.format` to
change the rendering.

## GitHub issues

With `github = { enabled = true }` and an authenticated
[gh](https://cli.github.com/) CLI, every comment in a repo with a github.com
`origin` is mirrored as an issue (title = description, body links the file and
hash). With `labels = true` the issue is labeled with the keyword (`todo`/`fix`)
and any `+tags` you typed in the prompt — GitHub labels must already exist in
the repo; if any are missing the issue is created without labels and you get a
warning. `extra_args` is appended to every `gh issue create` for assignees,
milestones, projects, etc. The mirroring is **push-only** and follows the sync
rules: removing the
comment closes the issue, restoring it reopens it. Changes made on GitHub are
never pulled — taskwarrior remains the local hub. (For pulling issues *into*
taskwarrior, see [bugwarrior](https://github.com/GothenburgBitFactory/bugwarrior);
it cannot create or close GitHub issues, which is why this uses `gh`.)

## Commands

`:TwTodo`, `:TwFix`, `:TwList`, `:TwSync` — all work without `setup()`.

## Roadmap

- [x] Insert TODO/FIX comments at cursor with a unique hash
- [x] Taskwarrior CLI interface (create a task per comment)
- [x] Sync: scan files, mark tasks whose comments are gone as completed
- [x] Project detection via root markers, used as the taskwarrior project
- [x] Urgency-sorted picker (tv.nvim / television, vim.ui.select fallback)
- [x] Virtual text with live task state
- [x] Rich input (due dates, priorities, tags)
- [x] GitHub issue mirroring (gh CLI, push-only)
