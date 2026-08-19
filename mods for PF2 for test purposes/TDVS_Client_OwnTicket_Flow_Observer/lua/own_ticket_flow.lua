_G.__TDVS_OWN_TICKET_OBSERVER = _G.__TDVS_OWN_TICKET_OBSERVER or {
    seq = 0,
    own_ticket_seq = 0,
    installed_peer = false,
    installed_session = false
}
local S = _G.__TDVS_OWN_TICKET_OBSERVER

local function logf(fmt, ...)
    S.seq = S.seq + 1
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    log(string.format("[TDVS OWN FLOW #%05d] %s", S.seq, msg))
end

local function safe(f, fallback)
    local ok, v = pcall(f)
    if ok then return v end
    return fallback
end

local function peer_id(p)
    return tostring(safe(function() return p:id() end, "?"))
end

local function account_id(p)
    return tostring(safe(function() return p:account_id() end, "?"))
end

local function local_account()
    return tostring(safe(function()
        local session = managers.network:session()
        local lp = session and session:local_peer()
        return lp and lp:account_id()
    end, "?"))
end

local function ticket_fp(t)
    if type(t) ~= "string" then return "nil" end
    -- Non-cryptographic diagnostic fingerprint; never log raw ticket.
    local h = 2166136261
    for i = 1, #t do
        h = (h * 16777619 + string.byte(t, i)) % 4294967296
    end
    return tostring(h)
end

local function join_state(session)
    if not session then return "session=nil" end
    local p = session._join_request_params
    local server = session._server_peer
    local stored = p and p.ticket
    return string.format(
        "server_peer=%s server_account=%s cb_find_game=%s join_params=%s stored_own_ticket_len=%s stored_fp=%s last_join_t=%s",
        tostring(server),
        server and account_id(server) or "nil",
        tostring(session._cb_find_game ~= nil),
        tostring(p ~= nil),
        type(stored) == "string" and tostring(#stored) or "nil",
        ticket_fp(stored),
        tostring(session._last_join_request_t)
    )
end

if NetworkPeer and not S.installed_peer then
    S.installed_peer = true

    if NetworkPeer.begin_ticket_session then
        local orig_begin = NetworkPeer.begin_ticket_session
        function NetworkPeer:begin_ticket_session(ticket, ...)
            local is_server_peer = safe(function()
                local sess = managers.network:session()
                return sess and sess._server_peer == self
            end, false)
            logf("HOST_TICKET_VALIDATION_BEGIN peer=%s account=%s local_account=%s is_server_peer=%s ticket_len=%s fp=%s",
                peer_id(self), account_id(self), local_account(), tostring(is_server_peer),
                type(ticket) == "string" and tostring(#ticket) or "nil", ticket_fp(ticket))
            return orig_begin(self, ticket, ...)
        end
    end

    if NetworkPeer.create_ticket then
        local orig_create = NetworkPeer.create_ticket
        function NetworkPeer:create_ticket(account_arg, callback, ...)
            S.own_ticket_seq = S.own_ticket_seq + 1
            local n = S.own_ticket_seq
            logf("OWN_TICKET_CREATE_BEGIN n=%d peer=%s peer_account=%s account_arg=%s local_account=%s",
                n, peer_id(self), account_id(self), tostring(account_arg), local_account())

            local wrapped = callback and function(ticket, ...)
                logf("=== OWN_TICKET_READY n=%d peer=%s account_arg=%s ticket_len=%s fp=%s ===",
                    n, peer_id(self), tostring(account_arg),
                    type(ticket) == "string" and tostring(#ticket) or "nil", ticket_fp(ticket))
                local sess = safe(function() return managers.network:session() end, nil)
                logf("OWN_TICKET_CALLBACK_BEFORE_ORIGINAL n=%d %s", n, join_state(sess))
                local r = { callback(ticket, ...) }
                local sess2 = safe(function() return managers.network:session() end, nil)
                logf("OWN_TICKET_CALLBACK_AFTER_ORIGINAL n=%d %s", n, join_state(sess2))
                logf("OWN_TICKET_HANDOFF_CONTEXT n=%d callback_returned=true", n)
                return unpack(r)
            end or nil

            local r = { orig_create(self, account_arg, wrapped, ...) }
            logf("OWN_TICKET_CREATE_END n=%d ret1_type=%s ret1_len=%s", n,
                type(r[1]), type(r[1]) == "string" and tostring(#r[1]) or "nil")
            return unpack(r)
        end
    end

    if NetworkPeer.on_verify_ticket then
        local orig_verify = NetworkPeer.on_verify_ticket
        function NetworkPeer:on_verify_ticket(result, reason, ...)
            local is_server_peer = safe(function()
                local sess = managers.network:session()
                return sess and sess._server_peer == self
            end, false)
            logf("HOST_TICKET_VERIFY_CALLBACK peer=%s account=%s is_server_peer=%s result=%s reason=%s",
                peer_id(self), account_id(self), tostring(is_server_peer), tostring(result), tostring(reason))
            return orig_verify(self, result, reason, ...)
        end
    end

    logf("NetworkPeer hooks installed")
end

if ClientNetworkSession and not S.installed_session then
    S.installed_session = true

    if ClientNetworkSession.on_auth_request_received then
        local orig_auth = ClientNetworkSession.on_auth_request_received
        function ClientNetworkSession:on_auth_request_received(reply, auth_ticket, sender, ...)
            logf("JOIN_AUTH_REQUEST_RECEIVED reply=%s host_ticket_len=%s host_ticket_fp=%s BEFORE{%s}",
                tostring(reply), type(auth_ticket) == "string" and tostring(#auth_ticket) or "nil",
                ticket_fp(auth_ticket), join_state(self))
            local r = { orig_auth(self, reply, auth_ticket, sender, ...) }
            logf("JOIN_AUTH_REQUEST_RETURN reply=%s AFTER{%s}", tostring(reply), join_state(self))
            return unpack(r)
        end
    end

    if ClientNetworkSession._upd_request_join_resend then
        local orig_resend = ClientNetworkSession._upd_request_join_resend
        function ClientNetworkSession:_upd_request_join_resend(wall_time, ...)
            local p = self._join_request_params
            if p and type(p.ticket) == "string" and #p.ticket > 0 then
                local now = tonumber(wall_time) or 0
                local last = tonumber(self._last_join_request_t)
                if last and now - last > ClientNetworkSession.HOST_REQUEST_JOIN_INTERVAL then
                    logf("OWN_TICKET_RESEND_OBSERVED ticket_len=%d fp=%s %s",
                        #p.ticket, ticket_fp(p.ticket), join_state(self))
                end
            end
            return orig_resend(self, wall_time, ...)
        end
    end

    logf("ClientNetworkSession hooks installed")
end

logf("loaded PASSIVE ONLY: no cancel, disconnect, delay, replay, ticket/JWT/callback/network mutation")
