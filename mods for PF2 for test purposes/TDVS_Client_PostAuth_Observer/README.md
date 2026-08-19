# TDVS Client Post-Auth Observer

Client-only, passive.

Purpose: mark the exact moment the client receives a successful `on_verify_ticket`
and then trace whether the game itself performs any later `create_ticket` or
`begin_ticket_session` lifecycle activity for the same peer.

This deliberately does **not** replay auth, delay callbacks, mutate JWTs, mutate
outfits, or touch `_join_request_params`.

Key markers:

- `=== AUTH_SUCCESS_MARKER`
- `create_ticket ... post_auth=true`
- `begin_ticket_session ... post_auth=true`

Recommended setup:
1. Disable the active lifecycle stress harness for this run.
2. Keep passive client inspector/trace if desired.
3. Keep the host `TDVS Pending Window Probe`.
4. Join normally once and perform ordinary lobby/game actions.
5. If a stock second auth lifecycle happens after success, both sides will log it.

If no post-auth ticket/begin occurs, that is still useful: it means the previously
observed duplicate-begin state requires an artificial replay rather than a normal
stock client lifecycle path.
