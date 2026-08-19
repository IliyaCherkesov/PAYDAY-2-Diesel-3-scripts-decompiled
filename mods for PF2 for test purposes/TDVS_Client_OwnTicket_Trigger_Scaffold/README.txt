TDVS Client Own-Ticket Trigger Scaffold

Purpose
-------
This is an intentionally inert SuperBLT scaffold for mapping the client-side
control point where the client's own TDVS authentication ticket is handed back
to the PAYDAY 2 join flow.

What it DOES:
- hooks NetworkPeer:create_ticket
- wraps the callback without changing the ticket
- lets the original callback run unchanged
- logs OWN_TICKET_CONTROL_POINT after the original callback returns

What it DOES NOT do:
- no timers
- no disconnect / leave_game / queue_stop_network
- no session teardown
- no ticket/JWT mutation
- no replay
- no callback suppression
- no packet/network modification

Expected markers:
CREATE_TICKET_BEGIN
OWN_TICKET_CALLBACK_ENTER
OWN_TICKET_CALLBACK_RETURN
=== OWN_TICKET_CONTROL_POINT ... ===
STUB_ONLY: no action taken
CREATE_TICKET_END

The scaffold is intentionally non-operational beyond logging the control point.
