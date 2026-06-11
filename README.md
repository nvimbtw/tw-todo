# tw-todo.nvim

Insert structured TODO/FIX comments and (eventually) sync them with
[taskwarrior](https://taskwarrior.org/).

Hitting a keybind opens a floating input; the description you type is inserted
above the cursor line as a comment, using the buffer's `commentstring`, together
with a unique hash that will later link the comment to a taskwarrior task:

```lua
-- TODO: fix the race in scheduler
-- tw:a3f9c12
```

## Setup

```lua
require("tw-todo").setup({
    keymaps = {
        todo = "<leader>tt", -- set to false to disable a mapping
        fix = "<leader>tf",
    },
    hash_prefix = "tw:", -- prefix on the hash line
    taskwarrior = {
        enabled = true, -- create a taskwarrior task when a comment is inserted
        command = "task",
        project = nil, -- string | fun(buf): string; default: git root (or cwd) directory name
    },
    sync = {
        on_write = true, -- reconcile comments with taskwarrior after saving a file (async)
    },
})
```

Created tasks get the description you typed, a `+todo`/`+fix` tag, a `project:`
from the directory name, and two UDAs: `twhash` (the comment's hash — the stable
link between code and task) and `twfile` (the file the comment lives in, relative
to the project root). The UDAs are passed as `rc.` overrides on every invocation,
so no `.taskrc` changes are needed.

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

The `:TwTodo` and `:TwFix` commands are also available without calling `setup()`.

## Roadmap

- [x] Insert TODO/FIX comments at cursor with a unique hash
- [x] Taskwarrior CLI interface (create a task per comment)
- [x] Sync: scan files, mark tasks whose comments are gone as completed
- [ ] Detect project/directory and use it as the taskwarrior tag
