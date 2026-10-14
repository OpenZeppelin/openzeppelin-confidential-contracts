---
'openzeppelin-confidential-contracts': minor
---

`BatcherConfidential`: Bubble up the `finalizeUnwrap` revert in `dispatchBatchCallback` unless the batch's unwrap request is no longer pending, so that a batch cannot proceed without having received its underlying tokens.
