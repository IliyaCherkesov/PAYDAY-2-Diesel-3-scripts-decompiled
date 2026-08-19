# Test results snapshot — 2026-08-15

## Test environment

Two PAYDAY 2 clients/accounts and machines controlled by the researcher were used. The host ran SuperBLT instrumentation for observation. The client could locally expose legitimate game content for mismatch testing, while remote ownership validation remained host-side.

Account identifiers are intentionally omitted from this public snapshot.

## Baseline TDVS token

Observed legitimate Steam TDVS payload fields:

```text
iss = p2wapi.paydaythegame.com
aud = PAYDAY_2_STEAM
account_type = STEAM
owned_dlc count = 5
```

The observed owned-app set contained the PAYDAY 2 base app plus four owned DLC/app identifiers. The tested Gage LMG Pack app (`275590`) was not present.

## Signature / parser negative tests

A token whose payload was edited while retaining the old signature reached the host and backend, but the backend rejected it with HTTP 401 / signature-verification failure.

Result:

```text
local JWT decode succeeds
host constructs pending cache
backend rejects altered token
cache does not gain forged ownership
```

A duplicate-key parser differential and an altered `sub` value were also tested as negative cases. They did not produce accepted forged ownership. An `account_type` mismatch can affect locally created metadata before backend rejection, which is a trust-asymmetry / robustness issue, not a demonstrated bypass.

## Valid baseline authentication

Valid TDVS validation follows:

```text
cache absent
→ TDVS begin
→ cache exists, pending=true, owned=0
→ HTTP 200 {"valid":true}
→ cache pending=false, owned=5
→ peer on_verify_ticket(true,"success")
→ deferred outfit verification runs
```

## Re-entrant valid authentication

Repeated valid authentication against an already-valid account cache was observed to create a new cache object:

```text
VALID: pending=false, owned=5
→ repeated valid begin
→ NEW CACHE: pending=true, owned=0
→ valid backend callback
→ pending=false, owned=5
```

This demonstrates a non-idempotent state replacement. No unowned-content acceptance was demonstrated during the window.

## Pending-window outfit behavior

While `_ticket_wait_response` / TDVS pending was active, outfit updates could arrive and be stored. Normal verification was deferred until successful ticket verification. This reduces exploitability of the transient empty ownership state through the obvious outfit path.

## Reconnect / peer lifetime

Multiple normal reconnects produced distinct peer generations. Normal teardown called TDVS end and removed the account cache:

```text
TDVS_END
→ cache_exists=false
→ pending=nil
→ owned=0
```

No cross-generation callback or ownership-cache inheritance was observed.

## Network transport failure

A controlled connectivity failure to `/tdvs/v1/validate_token` produced:

```text
error=0
status_code=0
response=""
```

Observed state after failure:

```text
cannot_reach_server = false
pending = false
owned = 0
peer verification callback absent
```

The peer remained in an incomplete authentication state rather than taking the documented fail-open path (`error==2` or HTTP 404). This is a concrete resilience/state-machine finding.

## Client own-ticket flow

The client first validates the **host's** ticket. That early client-side `NetworkPeer:begin_ticket_session()` is therefore the wrong direction for investigating host validation of the client.

The relevant flow is:

```text
client receives host auth request
→ client validates host ticket
→ client creates its own TDVS ticket
→ client sends own ticket to host
→ host begins TDVS validation of client
→ host sends join reply
```

## Join-phase correlation

Passive client observer markers:

```text
JOIN_AUTH_REQUEST_RECEIVED
OWN_TICKET_READY
OWN_TICKET_CALLBACK_RETURNED
HOST_JOIN_REPLY_AFTER_CLIENT_AUTH
HOST_JOIN_REPLY_RETURNED
```

The matching host run showed:

```text
NP_BEGIN
AUTH_GENERATION_BEGIN
TDVS_BEGIN
cache pending=true, owned=0
HTTP response after ~66 ms
VERIFY_CALLBACK
cache pending=false, owned=5
```

Therefore `HOST_JOIN_REPLY_AFTER_CLIENT_AUTH` proves the host-side begin has already happened, but it does **not** prove the host is still pending when the client sees the reply.

## Clock correlation

During the final correlation runs the client wall clock was approximately 3 minutes 56–57 seconds ahead of the host. This offset must be applied when comparing raw wall-clock log lines.

## Current conclusion

Confirmed:
- asynchronous host TDVS validation;
- join progression before TDVS callback;
- transient pending/empty ownership cache;
- non-idempotent re-auth replacement;
- normal teardown cache deletion;
- no normal cross-generation inheritance observed;
- transport-failure stuck state;
- post-begin client join-reply marker.

Not confirmed:
- stock ordinary-host DLC ownership bypass;
- client-controllable fail-open;
- stale callback poisoning a later peer generation;
- reliable ownership decision while the transient cache is empty.
