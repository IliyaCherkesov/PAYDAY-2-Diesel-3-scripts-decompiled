# Current open questions

Priority order for further research:

1. **Late callback after teardown**
   - Can a legitimate in-flight TDVS callback arrive after the peer/session has been ended?
   - Is the callback generation-bound?
   - Can it recreate or mutate account cache after cleanup?
   - Can a new peer generation with the same account ID be affected?

2. **Stock consumer inside the re-auth pending window**
   - Is there any normal host-side code path besides deferred outfit verification that consults ownership while a replacement auth cache is pending/empty?
   - If so, does it fail closed, fail open, or defer?

3. **Transport-failure semantics**
   - What runtime condition maps to `Distribution` error code `2`?
   - Why did a real connection failure produce `error=0,status_code=0`?
   - Is `cannot_reach_server` global and, if set, what resets it?

4. **Join-before-verdict impact**
   - Which host actions are reachable after `join_request_reply` but before `on_verify_ticket`?
   - Are any authorization-sensitive actions accepted in that interval?

5. **Duplicate begin behavior while already pending**
   - The implementation returns success when a cache is already pending.
   - Which peer/callback owns completion if multiple peer objects reference the same account?
   - Can this occur through a stock retry/reconnect path?

6. **Reason-code taxonomy**
   - Ownership mismatch currently converges on broad invalid-content / cheating handling.
   - A clearer taxonomy would distinguish malformed content, impossible content, and valid-but-unowned content.
