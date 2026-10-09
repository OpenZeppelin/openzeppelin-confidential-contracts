---
'openzeppelin-confidential-contracts': minor
---

`BatcherConfidential`: Revert `dispatchBatchCallback` with `UnwrapPending` when `finalizeUnwrap` fails while the batch's unwrap is still pending, instead of executing the route on funds the batcher has not received.
