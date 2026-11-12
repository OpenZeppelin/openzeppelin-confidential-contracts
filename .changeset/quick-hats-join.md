---
'openzeppelin-confidential-contracts': minor
---

`BatcherConfidential`: `_join` now returns an `ebool` indicating whether the join succeeded instead of the joined amount. `onConfidentialTransferReceived` uses it directly instead of computing `joinedAmount > 0`, saving one `FHE.gt` per callback deposit. Overrides of `_join` must update their signature.
