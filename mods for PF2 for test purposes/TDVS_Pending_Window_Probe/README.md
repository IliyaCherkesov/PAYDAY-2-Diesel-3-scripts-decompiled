# TDVS Pending Window Probe

HOST ONLY. Passive instrumentation for the already observed TDVS cache replacement window:

validated cache (`pending=false`, `owned>0`)
→ repeated `TDVS:begin_ticket_session`
→ new cache object (`pending=true`, `owned=0`)
→ validation callback
→ validated cache again.

The mod does not change any return value, JWT, outfit string, TDVS cache entry, peer field, anti-cheat decision, or network message.

## What to look for

The key markers are:

- `>>> ENTER_PENDING_WINDOW`
- `!!! CALL_DURING_PENDING_WINDOW ...`
- `!!! OWNERSHIP_DURING_PENDING_WINDOW ...`
- `<<< EXIT_PENDING_WINDOW`

It traces:
- `TDVS:is_user_product_owned`
- `NetworkPeer:set_outfit_string`
- `NetworkPeer:verify_outfit`
- `NetworkPeer:_verify_item_data`
- `NetworkPeer:_verify_content`
- `NetworkPeer:on_verify_ticket`
- `NetworkPeer:mark_cheater`

Each event includes the TDVS cache state and a best-effort Lua caller location.

## Test procedure

1. Install this on the host.
2. Keep the host behavior otherwise unchanged; passive tracers can remain enabled.
3. On the client, use the existing lifecycle harness only to reproduce the already-known duplicate-begin case.
4. Save both logs.
5. Search the host log for `ENTER_PENDING_WINDOW`, then inspect everything until `EXIT_PENDING_WINDOW`.

For a positive result (any ownership/verification call inside the window), one clean reproduction is enough to establish reachability. For a negative result, repeat the same case a few times because the window is timing-sensitive.
