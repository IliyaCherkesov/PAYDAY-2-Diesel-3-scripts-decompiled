TDVS Client Own-Ticket Flow Observer

Purpose
-------
Passive diagnostic observer. It distinguishes two easy-to-confuse flows on the client:
1) begin_ticket_session() on the server peer = CLIENT validating the HOST's ticket.
2) create_ticket(local_account, callback) = CLIENT obtaining its OWN ticket to send to the HOST.

This mod does NOT disconnect, cancel join, delay anything, replay authentication, alter JWTs/tickets, change callbacks, or modify network packets.

Use
---
Install only on the client. Disable the earlier active abort/join-cancel test mods. Keep the passive host TDVS probes enabled.
Perform one normal join and send both logs.

Important markers
-----------------
HOST_TICKET_VALIDATION_BEGIN    client starts validating host ticket (not our target)
OWN_TICKET_CREATE_BEGIN         client requests its own ticket
OWN_TICKET_READY                client's own ticket has been returned to game
OWN_TICKET_HANDOFF_CONTEXT      join state immediately after own ticket callback
OWN_TICKET_RESEND_OBSERVED      normal ClientNetworkSession resend loop sees own ticket already stored
HOST_TICKET_VERIFY_CALLBACK     client completes host-ticket validation

The own-ticket marker is what should be correlated with the host's TDVS_BEGIN for the client's account.
