local TAG = "[TDVS TRIGGER SCAFFOLD]"
local seq = 0
local wrapped = false

local function log(msg)
    seq = seq + 1
    local line = string.format("%s #%05d %s", TAG, seq, tostring(msg))
    if log then
        -- SuperBLT global log() may shadow this local name on some setups,
        -- so use io.write fallback below instead.
    end
    io.stdout:write(line .. "\n")
end

local function safe_account(peer)
    if not peer then
        return "nil"
    end
    local ok, v = pcall(function()
        return peer:account_id()
    end)
    return ok and tostring(v) or "?"
end

local function ticket_len(ticket)
    return type(ticket) == "string" and #ticket or -1
end

-- INTENTIONALLY INERT.
-- This function is the control-point stub. It only records that the
-- client's own authentication ticket has been handed back to the game.
-- No timer, disconnect, leave_game, session teardown, replay, mutation,
-- callback suppression, or network modification is implemented here.
local function control_point(peer, ticket)
    log(string.format(
        "=== OWN_TICKET_CONTROL_POINT peer_account=%s ticket_len=%d ===",
        safe_account(peer),
        ticket_len(ticket)
    ))

    log("STUB_ONLY: no action taken")
end

if NetworkPeer and NetworkPeer.create_ticket and not wrapped then
    wrapped = true
    local original_create_ticket = NetworkPeer.create_ticket

    function NetworkPeer:create_ticket(account_id, callback, ...)
        log(string.format(
            "CREATE_TICKET_BEGIN peer_account=%s account_arg=%s",
            safe_account(self),
            tostring(account_id)
        ))

        local original_callback = callback
        local peer_ref = self

        local function observed_callback(ticket, ...)
            log(string.format(
                "OWN_TICKET_CALLBACK_ENTER peer_account=%s ticket_len=%d",
                safe_account(peer_ref),
                ticket_len(ticket)
            ))

            -- Let the game's original callback run unchanged first.
            local results = { original_callback(ticket, ...) }

            log(string.format(
                "OWN_TICKET_CALLBACK_RETURN peer_account=%s ticket_len=%d",
                safe_account(peer_ref),
                ticket_len(ticket)
            ))

            control_point(peer_ref, ticket)

            return unpack(results)
        end

        local ret = original_create_ticket(self, account_id, observed_callback, ...)

        log(string.format(
            "CREATE_TICKET_END peer_account=%s return_type=%s",
            safe_account(self),
            type(ret)
        ))

        return ret
    end

    log("hook installed; scaffold is passive/inert")
else
    log("NetworkPeer:create_ticket unavailable or already wrapped")
end
