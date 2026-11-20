---
'openzeppelin-confidential-contracts': minor
---

`ERC7984`: `confidentialTransfer`, `confidentialTransferFrom`, `confidentialTransferAndCall` and `confidentialTransferFromAndCall` are no longer virtual and now call their `WithMemo` counterparts with an empty memo. Override the `WithMemo` variants to customize their behavior.
