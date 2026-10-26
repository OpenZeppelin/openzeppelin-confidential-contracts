---
'openzeppelin-confidential-contracts': minor
---

`BatcherConfidential`: Add `minExchangeRate`, the lowest exchange rate a batch can finalize at. It defaults to `1e3`, so rounding the rate down leaves less than 0.1% of a batch's output unclaimable.
