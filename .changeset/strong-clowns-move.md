---
'openzeppelin-confidential-contracts': minor
---

`BatcherConfidential`: replace `quit(uint256)` with `quit(uint256,address)` so callers can choose the refund recipient, update `_quit` accordingly, and include the recipient in `Quit` events.
