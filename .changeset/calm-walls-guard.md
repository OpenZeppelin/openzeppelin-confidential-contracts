---
'openzeppelin-confidential-contracts': patch
---

`BatcherConfidential`: Bubble up the `finalizeUnwrap` revert in `dispatchBatchCallback` unless it is `InvalidUnwrapRequest` for the batch's request, so that a batch cannot proceed without having received its underlying tokens.
