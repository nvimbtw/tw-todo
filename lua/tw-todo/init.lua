local M = {}

-- This is a change

function M.setup(opts)
    local config = require("tw-todo.config").apply(opts)
    local comment = require("tw-todo.comment")

    if config.keymaps.todo then
        vim.keymap.set("n", config.keymaps.todo, function()
            comment.insert("TODO")
        end, { desc = "tw-todo: insert TODO" })
    end
    if config.keymaps.fix then
        vim.keymap.set("n", config.keymaps.fix, function()
            comment.insert("FIX")
        end, { desc = "tw-todo: insert FIX" })
    end

    if config.keymaps.hover then
        vim.keymap.set("n", config.keymaps.hover, function()
            require("tw-todo.hover").show()
        end, { desc = "tw-todo: task details" })
    end
    if config.keymaps.develop and config.github.enabled then
        vim.keymap.set("n", config.keymaps.develop, function()
            require("tw-todo.github").develop_at_cursor()
        end, { desc = "tw-todo: develop branch for issue" })
    end

    if config.keymaps.list then
        vim.keymap.set("n", config.keymaps.list, function()
            require("tw-todo.picker").open()
        end, { desc = "tw-todo: list tasks" })
    end

    local group = vim.api.nvim_create_augroup("TwTodoSync", { clear = true })
    if config.taskwarrior.enabled and config.sync.on_write then
        vim.api.nvim_create_autocmd("BufWritePost", {
            group = group,
            callback = function(ev)
                require("tw-todo.sync").sync_buffer(ev.buf)
            end,
        })
    end
    if config.taskwarrior.enabled and config.virtual_text.enabled then
        vim.api.nvim_create_autocmd("BufReadPost", {
            group = group,
            callback = function(ev)
                require("tw-todo.virtual").refresh(ev.buf)
            end,
        })
    end
end

return M
