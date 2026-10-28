---
'openzeppelin-confidential-contracts': minor
---

`BatcherConfidential`: Add the internal `_validateExchangeRate` hook, which `dispatchBatchCallback` calls to accept or reject a batch's exchange rate. It rejects only `0` by default; override it to require a minimum rate.
