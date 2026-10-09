---
'openzeppelin-confidential-contracts': patch
---

`BatcherConfidential`: Bubble up the `finalizeUnwrap` revert in `dispatchBatchCallback` when the unwrap request is still pending, so that a batch cannot proceed without having received its underlying tokens.
