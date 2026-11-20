---
'openzeppelin-confidential-contracts': minor
---

`BatcherConfidential`: `_join` now returns `(ebool success, euint64 joinedAmount)`. `onConfidentialTransferReceived` uses `success` directly instead of computing `joinedAmount > 0`, saving one `FHE.gt` per callback deposit. Overrides of `_join` must update their signature.
