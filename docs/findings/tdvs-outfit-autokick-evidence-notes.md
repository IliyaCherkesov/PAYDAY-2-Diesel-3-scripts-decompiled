# Evidence notes

These notes are intended for repository maintainers and reviewers.

## Confirmed runtime observations

- Host begins TDVS validation with `pending=true`.
- Host sends join-related RPCs before the TDVS callback completes.
- Stored outfit is validated after successful TDVS completion.
- Unowned DLC produces an ownership failure and `reason=9`.
- `mark_cheater()` receives `auto_kick=true`.
- In the normal timing path, the peer is marked `cheater=true` but remains connected.
- Repeated validation of the same invalid item does not emit the cheat reason again.
- In the delayed-control run, the peer was removed when `_begin_ticket_session_called` was already `nil`.

## Confirmed static observations

- `_begin_ticket_session_called` is set before the TDVS request.
- The TDVS callback invokes `on_verify_ticket()` before clearing `_begin_ticket_session_called`.
- `on_verify_ticket()` can trigger `verify_outfit()`.
- `mark_cheater()` forwards `_begin_ticket_session_called` to `kick_auto()` as the loading argument.
- `kick_auto()` only performs the actual peer removal when `loading` is false/nil.
- duplicate invalid outfit items are suppressed through `_cheated_items`.

## Interpretation

The vulnerability is not a failure to detect DLC ownership. It is a failure to carry a valid detection through to the configured automatic enforcement action because the detection occurs during the wrong lifecycle state.
