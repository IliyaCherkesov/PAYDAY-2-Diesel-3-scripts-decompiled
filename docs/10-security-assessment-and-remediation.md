# Security assessment and reporting language

## Demonstrated findings

### A. Re-entrant authentication replaces validated entitlement state

A repeated **valid** authentication can replace:

```text
pending=false, owned=N
```

with:

```text
pending=true, owned=0
```

until the new backend response completes.

Suggested classification: authentication/authorization state-machine robustness issue; transient entitlement-state replacement.

Do not describe this alone as an ownership bypass.

### B. Transport failure can leave authentication incomplete

A real transport failure to `validate_token` was observed to produce `error=0,status_code=0`, not the implementation's fail-open condition. The normal verification callback was not delivered and the peer remained in an incomplete state.

Suggested classification: authentication availability / incomplete-state handling.

### C. Join progression begins before asynchronous validation completes

The host can acknowledge join progression after successfully **starting** TDVS validation rather than after receiving the backend verdict.

Suggested classification: asynchronous authentication sequencing / trust-boundary observation.

This becomes security-sensitive only if a protected action is accepted before the verdict.

### D. Pre-validation metadata trust asymmetry

Decoded JWT fields can influence local cache metadata before the backend signature verdict. Invalidly signed mutations tested so far were rejected by the backend and did not produce forged ownership.

Suggested classification: defense-in-depth / parser and metadata trust asymmetry.

## What is not currently demonstrated

- forged signed token acceptance;
- forged DLC ownership;
- stock client-controlled `cannot_reach_server` fail-open;
- cross-generation stale-cache inheritance;
- ordinary-host authorization bypass;
- reliable client-side race exploitation.

## Recommended remediation ideas

1. Preserve the previous validated cache until replacement authentication succeeds; commit new state atomically.
2. Bind asynchronous callbacks to both peer object/generation and authentication generation.
3. Treat teardown as cancellation and ignore callbacks whose generation is no longer current.
4. Do not progress security-sensitive join actions until the remote authentication verdict is finalized.
5. Normalize network transport failures into explicit, bounded failure states; avoid stuck `_ticket_wait_response`.
6. Keep entitlement lookup behavior consistent between missing cache, pending cache, rejected cache, and backend-unavailable states.
7. Distinguish invalid content from ownership mismatch in reason codes rather than conflating all cases into a generic cheating reason.
