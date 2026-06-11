-- INFO: Small shared helpers (taskwarrior timestamp conversion)

local M = {}

--- Epoch seconds for a taskwarrior UTC timestamp ("20260630T220000Z").
---@param ts string
---@return integer|nil
function M.utc_epoch(ts)
    local y, m, d, H, Mi, S = ts:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z$")
    if not y then
        return nil
    end
    -- os.time reads the fields as local time; correct by comparing against the
    -- same instant's UTC field set (isdst left to libc, or DST is off by 1h)
    local guess = os.time({ year = y, month = m, day = d, hour = H, min = Mi, sec = S })
    local utc_fields = os.date("!*t", guess) --[[@as osdate]]
    utc_fields.isdst = nil
    local offset = os.difftime(guess, os.time(utc_fields))
    return guess + offset
end

--- taskwarrior timestamps are UTC; render the local date.
---@param ts string
---@return string
function M.local_date(ts)
    local epoch = M.utc_epoch(ts)
    if not epoch then
        return ts
    end
    return os.date("%Y-%m-%d", epoch) --[[@as string]]
end

return M
