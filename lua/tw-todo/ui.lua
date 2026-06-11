-- INFO: Floating input window

local M = {}

function M.input(prompt, callback)
    local buf = vim.api.nvim_create_buf(false, true)

    local width = 50
    local height = 3
    local opts = {
        relative = 'editor',
        width = width,
        height = height,
        col = math.floor((vim.o.columns - width) / 2),
        row = math.floor((vim.o.lines - height) / 2),
        anchor = 'NW',
        style = 'minimal',
        border = 'single',
    }

    local win = vim.api.nvim_open_win(buf, true, opts)

    -- Set the prompt as the first line, user types on second
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { prompt, "" })

    -- Put cursor on the input line
    vim.api.nvim_win_set_cursor(win, { 2, 0 })

    -- Start in insert mode
    vim.cmd("startinsert")

    local function confirm()
        local line = vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]
        vim.api.nvim_win_close(win, true)
        vim.cmd("stopinsert")
        -- Treat an empty description as a cancel
        if line == nil or line:match("^%s*$") then
            callback(nil)
        else
            callback(line)
        end
    end

    local function cancel()
        vim.api.nvim_win_close(win, true)
        vim.cmd("stopinsert")
        callback(nil)
    end

    vim.keymap.set('i', '<CR>', confirm, { buffer = buf, noremap = true, silent = true })
    vim.keymap.set('i', '<Esc>', cancel, { buffer = buf, noremap = true, silent = true })
    vim.keymap.set('n', '<Esc>', cancel, { buffer = buf, noremap = true, silent = true })
    vim.keymap.set('n', 'q', cancel, { buffer = buf, noremap = true, silent = true })
end

return M
