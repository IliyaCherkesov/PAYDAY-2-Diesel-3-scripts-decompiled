# PAYDAY 2 Update 247 / TDVS reverse-engineering notes

This repository is a sanitized research snapshot assembled from static analysis and controlled two-machine tests performed on accounts and machines under the researcher's control.

## Scope

The work covers:

- Diesel 3.0 `YAOI` / `.crate` extraction;
- LuaJIT decompilation workflow;
- local DLC / entitlement state;
- TDVS ticket acquisition and remote validation;
- host-side ownership cache lifecycle;
- outfit/content verification;
- reconnect / peer-generation behavior;
- network-failure behavior;
- client/host join-phase correlation.

The repository intentionally contains passive instrumentation and documentation, not a portable ownership-bypass tool.

## Most important current findings

1. **Join is acknowledged before asynchronous TDVS validation completes.** The host starts `begin_ticket_session(client_ticket)` and can send `join_request_reply` immediately after the synchronous begin returns true.
2. **TDVS validation replaces ownership state with a pending empty cache.** At begin: `pending_owned_dlc=true`, `owned_dlc={}`. On a valid callback, it becomes `pending=false` with the decoded owned-DLC list.
3. **Valid re-entrant authentication is not state-idempotent.** A repeated valid begin can replace an already valid cache with a new `pending=true, owned=0` object until the second callback completes.
4. **Observed transport failure can leave authentication stuck.** A real `/validate_token` transport failure produced `error=0,status_code=0`, left `pending=false, owned=0`, and did not deliver the normal peer verification callback. The documented `cannot_reach_server` fail-open condition did not activate in that test.
5. **Normal reconnects did not inherit prior TDVS state.** Peer generations were distinct and normal teardown deleted the account cache before the next generation.
6. **Client-visible join reply is a post-begin marker, but not a guaranteed pending-window marker.** In a measured run the host backend validation completed in ~66 ms, fast enough that the client received the join reply after validation had already completed.

## Security status

Several robustness/state-machine flaws are demonstrated. A stock, ordinary-host ownership bypass has **not** been demonstrated in the included evidence. Findings should therefore be described precisely rather than as a confirmed DLC-authentication bypass.

See `docs/08-test-results-2026-08-15.md`, `docs/09-state-machine-findings.md`, and `docs/11-open-questions-current.md`.
