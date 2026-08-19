# Sanitized evidence timeline

Identifiers are replaced with `CLIENT_ACCOUNT` / `HOST_ACCOUNT`. Raw reusable authentication tokens are not included.

## Final join-phase correlation

Client:

```text
01:14:24 JOIN_AUTH_REQUEST_RECEIVED
01:14:24 OWN_TICKET_CREATE_BEGIN
01:14:25 HOST_TICKET_VERIFY_CALLBACK result=true
01:14:27 OWN_TICKET_READY
01:14:27 OWN_TICKET_CALLBACK_RETURNED
01:14:27 HOST_JOIN_REPLY_AFTER_CLIENT_AUTH
01:14:27 HOST_JOIN_REPLY_RETURNED
```

Matching host after applying the ~3m57s wall-clock offset:

```text
01:10:30 NP_BEGIN
01:10:30 AUTH_GENERATION_BEGIN
01:10:30 TDVS_BEGIN
01:10:30 state: cache_exists=true pending=true owned=0
01:10:30 validate_token RESPONSE elapsed_ms=66 HTTP 200 {"valid":true}
01:10:30 VERIFY_CALLBACK_BEGIN result=true reason=success
01:10:30 state: pending=false owned=5
```

Interpretation: the client join-reply marker is post-host-begin, but backend completion may precede receipt of the marker.

## Normal teardown

Representative host state:

```text
before TDVS_END: cache_exists=true pending=false owned=5
TDVS_END
after TDVS_END: cache_exists=false pending=nil owned=0
```

This was observed before later fresh peer generations.

## Re-entrant valid authentication

Representative state transition:

```text
before repeated begin:
  cache_exists=true
  pending=false
  owned=5

after repeated begin:
  cache object replaced
  pending=true
  owned=0

after valid callback:
  pending=false
  owned=5
```

## Transport failure

Representative endpoint failure:

```text
validate_token:
  error=0
  status_code=0
  response=""

after failure:
  cannot_reach_server=false
  pending=false
  owned=0
  no normal peer verify callback observed
```
