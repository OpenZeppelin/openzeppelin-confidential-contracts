---
'openzeppelin-confidential-contracts': minor
---

`ERC7984`: `confidentialTransfer`, `confidentialTransferFrom`, `confidentialTransferAndCall` and `confidentialTransferFromAndCall` are no longer virtual and now call their overload with a trailing `bytes32 memo` argument, passing an empty memo. Override the memo overloads to customize their behavior.
