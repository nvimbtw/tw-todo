# tw-todo.nvim

Structured TODO/FIX comments that live in your code and stay in lockstep with
[taskwarrior](https://taskwarrior.org/) — and optionally with GitHub issues.

Hitting a keybind opens a floating input; the description you type is inserted
above the cursor line as a comment, using the buffer's `commentstring`, together
with a unique hash linking the comment to a taskwarrior task. Due date and tags
are part of the comment block (visible to anyone — or any agent — reading the
file); everything else lives in taskwarrior and shows up in the hover:

```lua
-- TODO: fix the race in scheduler
-- tw:   a3f9c12
-- due:  2026-06-20
-- tags: +urgent +concurrency
```

The `due:`/`tags:` lines only appear when set, and editing them syncs back to
taskwarrior (and GitHub labels) on save — see [Sync](#sync).

## Setup

```lua
require("tw-todo").setup({
    keymaps = {
        todo = "<leader>tt", -- set any of these to false to disable the mapping
        fix = "<leader>tf",
        list = "<leader>tl", -- task picker
        hover = "<leader>ti", -- float with full task details for the comment under the cursor
        develop = "<leader>tb", -- create + checkout the gh develop branch for the comment's issue
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
        enabled = true, -- show a small severity indicator next to hash lines
        soon_days = 3, -- due within this many days renders as a warning
        format = nil, -- fun(task|nil): chunks — override the rendering
    },
    merge = {
        enabled = true, -- offer merging a develop branch back into its base when its task completes
        message = "close #%d: %s", -- commit message for the comment-removal commit (issue, description)
        delete_branch = true, -- delete the local develop branch after merging (the remote is never touched)
    },
    github = {
        enabled = false, -- mirror comments as GitHub issues via the gh CLI
        command = "gh",
        labels = true, -- label issues with the keyword (todo/fix) and your +tags
        extra_args = {}, -- passed to `gh issue create`, e.g. { "--assignee", "@me", "--milestone", "v1.0" }
        develop = {
            start_task = true, -- `task start` the task after checking out its develop branch
        },
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
recur: depends:`.) `due:` and `+tags` are also written into the comment block —
fuzzy dates like `due:friday` are rewritten to the resolved date once the task
lands. The other attributes live only in taskwarrior (visible in the hover) and
are lost if the task is purged and recreated.

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
| `due:`/`tags:` lines edited | pending | task (and issue labels) updated |

For metadata the comment wins too: deleting the `due:` line clears the task's
due date, and the `tags:` line is the full set of user tags (the keyword tag is
kept implicitly). A comment without a `tags:` line expresses no opinion, so
tags added via the CLI to old-style comments survive. After a metadata edit the
buffer's block is rewritten in canonical form (resolved dates, padded keys).

## Picker

`:TwList` (default `<leader>tl`) lists the project's pending tasks sorted by
taskwarrior **urgency** and jumps to the comment on selection.

With [tv.nvim](https://github.com/alexpasmantier/tv.nvim) installed it opens a
[television](https://github.com/alexpasmantier/television) channel (the cable
definition is auto-installed to `~/.config/television/cable/tw-todo.toml` on
first use, and also works standalone: `tv tw-todo` from a project directory).
Without tv.nvim it falls back to `vim.ui.select`.

## Hover

`:TwHover` (default `<leader>ti`) on any line of a comment block opens a float
with everything that is not in the comment: status, urgency, priority, project,
tags, all dates (due/scheduled/wait/until/recur), tracking state, annotations,
and the mirrored GitHub issue number. Invoke it twice to focus the float
(standard `K` behavior).

## Virtual text

Each hash line shows a small severity indicator after reads, saves, and
inserts: `● 8.2` (urgency) colored `TwTodoPending` (info) normally,
`TwTodoDue` (warn) when due within `soon_days`, `TwTodoOverdue` (error) when
overdue; `▶` prepended while the task is active (`TwTodoActive`); the status
word for non-pending tasks or `untracked` (`TwTodoUntracked`) for hashes
taskwarrior doesn't know. Due dates and tags are shown in the comment itself,
the rest in the hover. Override the highlight groups or pass
`virtual_text.format` to change the rendering.

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

Editing a comment's `tags:` line also updates the issue's labels on save
(`gh issue edit --add-label/--remove-label`, skipped with a warning for labels
missing from the repo).

### Develop branches

`:TwDevelop` (default `<leader>tb`) on a comment block creates the
issue-linked branch via `gh issue develop --base <current branch>`, after a
confirmation prompt showing the exact branch name
(`<issue>-<description-slug>`, gh's own convention). The local switch is
`git switch -C` at your current HEAD — unlike gh's own `--checkout` it works
with a dirty worktree (inserting a comment always leaves one) and your
uncommitted changes come along to the new branch. The remote branch gh
registered is set as upstream so a later plain `git push` does the right
thing. With `develop.start_task = true` the taskwarrior task is `start`ed so
the virtual text shows `▶`. The branch and the branch it was created from are
recorded on the task (`twbranch`/`twbase` UDAs) — that is how the merge-back
knows its target.

### Merge-back

Deleting the comment block and saving is already how a task completes; when
the completed task has a recorded develop branch and you are on it, the work
is done by definition and the plugin offers (confirm prompt) to merge it
back:

1. the comment-removal is committed — only the comment's file; if anything
   else is uncommitted the flow aborts with a notify instead of sweeping it in
   (`merge.message`, default `close #N: <description>`, so the push will also
   close the issue server-side)
2. `git switch <base>` + `git merge --no-ff <branch>` (conflicts are left to
   you to resolve normally)
3. the local branch is deleted (`merge.delete_branch`); the remote linked
   branch stays — deleting it would require a push, and the plugin never
   pushes
4. `twbranch`/`twbase` are cleared, marking the task merged

When several comments are removed in one save (agents do this), the commit
message credits all of them (`closes #N: …` body lines) and at most one merge
prompt fires — branches finished while you were elsewhere are listed by
`:TwMerge`, the deferred/retry path (declined prompt, wrong branch, dirty
tree). Disable the whole behavior with `merge.enabled = false`.

## Commands

`:TwTodo`, `:TwFix`, `:TwList`, `:TwSync`, `:TwHover`, `:TwDevelop`,
`:TwMerge` — all work without `setup()`.

## Roadmap

- [x] Insert TODO/FIX comments at cursor with a unique hash
- [x] Taskwarrior CLI interface (create a task per comment)
- [x] Sync: scan files, mark tasks whose comments are gone as completed
- [x] Project detection via root markers, used as the taskwarrior project
- [x] Urgency-sorted picker (tv.nvim / television, vim.ui.select fallback)
- [x] Virtual text with live task state
- [x] Rich input (due dates, priorities, tags)
- [x] GitHub issue mirroring (gh CLI, push-only)
- [x] Due/tags as comment lines, two-way synced to taskwarrior and issue labels
- [x] Hover float with full task details
- [x] `gh issue develop` branches from a comment (confirmed, checkout, `task start`)
- [x] Auto merge-back: task completion commits the removal and merges the develop branch into its recorded base (commit-only, no push)
