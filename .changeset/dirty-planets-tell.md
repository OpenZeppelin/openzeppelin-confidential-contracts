---
'openzeppelin-confidential-contracts': minor
---

`IERC7984` and `ERC7984`: Add a `bytes32 indexed memo` field to the `ConfidentialTransfer` event (`amount` is no longer indexed), and add overloads of `confidentialTransfer`, `confidentialTransferFrom`, `confidentialTransferAndCall` and `confidentialTransferFromAndCall` that take a trailing `bytes32 memo` argument. The internal `_mint`, `_burn`, `_transfer`, `_transferAndCall` and `_update` functions take an additional `bytes32 memo` parameter. Public confidential transfer functions without input proofs have been removed.