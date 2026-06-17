---
'openzeppelin-confidential-contracts': patch
---

`BatcherConfidential`: Materialize the unwrap handle when dispatching an empty batch so dispatch passes a real, transiently-allowed handle to `fromToken().unwrap` instead of the raw uninitialized (zero) handle.
