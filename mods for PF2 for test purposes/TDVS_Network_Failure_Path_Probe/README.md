# TDVS Network Failure Path Probe

Two passive SuperBLT probes:

- `HOST_TDVS_Network_Failure_Path_Probe`
- `CLIENT_TDVS_Network_Failure_Path_Probe`

They do not block traffic and do not change TDVS behavior. They only record what
the stock game decides when the TDVS validation backend is reachable or unreachable.

Recommended controlled test on your own host/client:

1. Disable active lifecycle/tamper harnesses.
2. Keep `TDVS Validate HTTP Trace v2` enabled on the host if you already have it.
3. Install both probes and start both games fresh.
4. Baseline: join once with normal network access and save both logs.
5. Failure case: make the host machine unable to reach the TDVS validation backend
   using your normal local firewall/DNS/network controls, then join once.
6. Restore network access immediately after the test and save both logs.

Do not spoof backend responses and do not modify JWTs for this test.

Important host markers:

- `VERIFY_CALLBACK_BEGIN ... result=... reason=...`
- `>>> NETWORK_FAILURE_ACCEPTED`
- `NETWORK_FAILURE_REJECTED`
- `OWNERSHIP_BEGIN/END`
- `VERIFY_OUTFIT_BEGIN/END`
- `MARK_CHEATER`

The key question is whether a genuine transport/backend reachability failure causes
the unmodified host to independently accept authentication or ownership in a state
that differs from the normal validated path.
