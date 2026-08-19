_G.__TDVS_JOIN_PHASE_OBSERVER = _G.__TDVS_JOIN_PHASE_OBSERVER or {
    seq = 0,
    own_seq = 0,
    installed_peer = false,
    installed_session = false
}
local S = _G.__TDVS_JOIN_PHASE_OBSERVER

local function logf(fmt, ...)
    S.seq = S.seq + 1
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    log(string.format("[TDVS JOIN PHASE #%05d] %s", S.seq, msg))
end

local function safe(f, fallback)
    local ok, v = pcall(f)
    if ok then return v end
    return fallback
end

local function aid(p)
    return tostring(safe(function() return p and p:account_id() end, "nil"))
end

local function pid(p)
    return tostring(safe(function() return p and p:id() end, "nil"))
end

local function fp(t)
    if type(t) ~= "string" then return "nil" end
    local h = 2166136261
    for i = 1, #t do
        h = (h * 16777619 + string.byte(t, i)) % 4294967296
    end
    return tostring(h)
end

local function state(sess)
    if not sess then return "session=nil" end
    local sp = sess._server_peer
    local jp = sess._join_request_params
    local t = jp and jp.ticket
    return string.format(
        "server_peer=%s server_id=%s server_account=%s cb=%s join_params=%s own_ticket_len=%s own_fp=%s last_join_t=%s",
        tostring(sp), pid(sp), aid(sp), tostring(sess._cb_find_game ~= nil), tostring(jp ~= nil),
        type(t) == "string" and tostring(#t) or "nil", fp(t), tostring(sess._last_join_request_t)
    )
end

if NetworkPeer and not S.installed_peer then
    S.installed_peer = true

    if NetworkPeer.create_ticket then
        local orig = NetworkPeer.create_ticket
        function NetworkPeer:create_ticket(account_arg, callback, ...)
            S.own_seq = S.own_seq + 1
            local n = S.own_seq
            logf("OWN_TICKET_CREATE_BEGIN n=%d peer=%s peer_account=%s account_arg=%s", n, pid(self), aid(self), tostring(account_arg))
            local wrapped = callback and function(ticket, ...)
                logf("=== OWN_TICKET_READY n=%d len=%s fp=%s ===", n, type(ticket)=="string" and tostring(#ticket) or "nil", fp(ticket))
                local r = { callback(ticket, ...) }
                local sess = safe(function() return managers.network:session() end, nil)
                logf("OWN_TICKET_CALLBACK_RETURNED n=%d %s", n, state(sess))
                return unpack(r)
            end or nil
            local r = { orig(self, account_arg, wrapped, ...) }
            logf("OWN_TICKET_CREATE_END n=%d", n)
            return unpack(r)
        end
    end

    if NetworkPeer.on_verify_ticket then
        local orig = NetworkPeer.on_verify_ticket
        function NetworkPeer:on_verify_ticket(result, reason, ...)
            logf("HOST_TICKET_VERIFY_CALLBACK peer=%s account=%s result=%s reason=%s", pid(self), aid(self), tostring(result), tostring(reason))
            return orig(self, result, reason, ...)
        end
    end

    logf("NetworkPeer hooks installed")
end

if ClientNetworkSession and not S.installed_session then
    S.installed_session = true

    if ClientNetworkSession.on_auth_request_received then
        local orig = ClientNetworkSession.on_auth_request_received
        function ClientNetworkSession:on_auth_request_received(reply, auth_ticket, sender, ...)
            logf("JOIN_AUTH_REQUEST_RECEIVED reply=%s host_ticket_len=%s host_fp=%s BEFORE{%s}", tostring(reply), type(auth_ticket)=="string" and tostring(#auth_ticket) or "nil", fp(auth_ticket), state(self))
            local r = { orig(self, reply, auth_ticket, sender, ...) }
            logf("JOIN_AUTH_REQUEST_RETURNED reply=%s AFTER{%s}", tostring(reply), state(self))
            return unpack(r)
        end
    end

    if ClientNetworkSession.on_join_request_reply then
        local orig = ClientNetworkSession.on_join_request_reply
        function ClientNetworkSession:on_join_request_reply(reply, my_peer_id, my_character, level_index, difficulty_index, one_down, state_index, server_character, user_id, mission, job_id_index, job_stage, alternative_job_stage, interupt_job_stage_level_index, xuid, sender, ...)
            logf("=== HOST_JOIN_REPLY_AFTER_CLIENT_AUTH reply=%s my_peer_id=%s state_index=%s host_user_id=%s BEFORE{%s} ===", tostring(reply), tostring(my_peer_id), tostring(state_index), tostring(user_id), state(self))
            local r = { orig(self, reply, my_peer_id, my_character, level_index, difficulty_index, one_down, state_index, server_character, user_id, mission, job_id_index, job_stage, alternative_job_stage, interupt_job_stage_level_index, xuid, sender, ...) }
            logf("HOST_JOIN_REPLY_RETURNED reply=%s AFTER{%s}", tostring(reply), state(self))
            return unpack(r)
        end
    end

    logf("ClientNetworkSession hooks installed")
end

logf("loaded PASSIVE ONLY; key marker=HOST_JOIN_REPLY_AFTER_CLIENT_AUTH; no timing/cancel/disconnect/replay/mutation")
