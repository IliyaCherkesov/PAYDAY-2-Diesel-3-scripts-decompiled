# TDVS Session Generation Probe

Two passive SuperBLT mods:

- `HOST_TDVS_Session_Generation_Probe`
- `CLIENT_TDVS_Session_Generation_Probe`

They only log session/peer/auth generations. They do not replay auth, delay callbacks,
change tickets, alter TDVS cache, change peer fields, or modify anti-cheat decisions.

## Test

Disable the active lifecycle stress harness for this test.

1. Install the HOST folder on the host and the CLIENT folder on the client.
2. Start both games fresh.
3. Join the host normally and wait until fully authenticated.
4. Leave/disconnect normally.
5. Rejoin the same host normally.
6. Repeat once more if convenient.
7. Send both SuperBLT logs.

Useful host markers:

- `PEER_GENERATION_CREATE`
- `AUTH_GENERATION_BEGIN`
- `VERIFY_TICKET_CALLBACK`
- `PEER_END_DONE`
- `!!! CROSS_GENERATION_CALLBACK`

A `CROSS_GENERATION_CALLBACK` marker would mean a callback tied to one peer generation
arrived while a different peer generation for the same account was current.
