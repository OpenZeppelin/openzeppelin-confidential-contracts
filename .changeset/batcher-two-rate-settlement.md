---
'openzeppelin-confidential-contracts': minor
---

`BatcherConfidential`: Replace the `Complete`/`Partial`/`Cancel` route outcomes with a single finalization that wraps both underlying balances and pins an `exchangeRate` and a `refundRate`, so `claim` pays depositors in both tokens. A reverting route rewraps the input and leaves the batch `Failed`, from where depositors can `quit` and anyone can `redispatchBatch`. Routes that send the input to an external service leave the batch `Settling` until `settleBatch` receives the outcome. At most one batch is in flight at a time. The `Canceled` state, `BatchCanceled` event and `ExecuteOutcome` enum are removed; `_executeRoute` returns a `bool` and the new `_settleRoute` must be implemented. The route runs with a calibrated gas budget, `_routeGasLimit`, which callbacks must fund in full.
