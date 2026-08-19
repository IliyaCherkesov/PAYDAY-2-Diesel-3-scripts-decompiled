# TDVS state-machine findings

## Host authentication order

Static analysis of `HostStateInLobby:on_join_auth_received()` indicates the host begins ticket validation and, if the synchronous begin succeeds, constructs the successful join reply without waiting for the asynchronous validation callback.

Conceptually:

```text
client ticket received
→ new_peer:begin_ticket_session(ticket)
   → TDVS:begin_ticket_session(...)
      → parse JWT
      → create pending cache
      → POST /tdvs/v1/validate_token
      → return true immediately
→ host sends join_request_reply(OK,...)
→ backend callback arrives later
→ NetworkPeer:on_verify_ticket(...)
```

This ordering was consistent with passive runtime traces.

## Ownership cache states

### Missing

```text
peer_tickets[account] == nil
```

Observed code path in ownership lookup treats missing TDVS cache differently from an existing empty cache.

### Pending

```text
peer_tickets[account] = {
    pending_owned_dlc = true,
    owned_dlc = {}
}
```

### Valid

```text
pending_owned_dlc = false
owned_dlc = [validated app IDs...]
```

### Rejected / failed

Depending on failure type, observed states include an existing empty cache with `pending=false`, or an authentication flow that fails to deliver the normal peer callback.

## Re-entrant replacement

A second valid begin after successful authentication can replace the valid cache with a fresh pending object rather than preserving the previous validated ownership until replacement validation succeeds.

Security interpretation:

- confirmed: state is non-idempotent and temporarily loses validated ownership;
- unconfirmed: whether an ordinary stock message consumer can make a security-sensitive decision in that exact window.

## Teardown

Normal `end_ticket_session()` removes the account cache. Reconnect experiments showed a fresh peer object/generation and no normal ownership inheritance.

## Late-callback question

The high-value unresolved lifecycle question is whether a backend callback can arrive after peer/session teardown and, if so, whether it can recreate or mutate state belonging to a dead or replacement generation.

This repository does not claim that behavior has been demonstrated.
