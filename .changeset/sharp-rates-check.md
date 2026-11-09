---
'openzeppelin-confidential-contracts': minor
---

`BatcherConfidential`: Add the internal `_validateExchangeRate` hook, which `dispatchBatchCallback` calls to accept or reject a batch's exchange rate. It accepts any rate by default (`dispatchBatchCallback` always rejects `0`).