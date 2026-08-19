TDVS Client Join Phase Observer

Purpose
-------
Passive mapping of the client join/auth protocol. The important marker is:

    === HOST_JOIN_REPLY_AFTER_CLIENT_AUTH ===

In the stock flow this incoming join_request_reply is sent by HostStateInLobby:on_join_auth_received only after the host has called new_peer:begin_ticket_session(auth_ticket) and that call returned true. Therefore it is a deterministic protocol phase marker; it is not based on elapsed time.

The observer does NOT disconnect the client, alter tickets, replay auth, suppress callbacks, mutate packets, or change return values.

Useful markers
--------------
JOIN_AUTH_REQUEST_RECEIVED
OWN_TICKET_READY
OWN_TICKET_CALLBACK_RETURNED
=== HOST_JOIN_REPLY_AFTER_CLIENT_AUTH ===
HOST_JOIN_REPLY_RETURNED
HOST_TICKET_VERIFY_CALLBACK

Keep host passive TDVS lifecycle probes enabled and correlate this marker with host TDVS_BEGIN / VALIDATE HTTP / VERIFY_CALLBACK / TDVS_END.
