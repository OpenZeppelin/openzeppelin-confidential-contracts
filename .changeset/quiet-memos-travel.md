---
'openzeppelin-confidential-contracts': minor
---

`IERC7984` and `ERC7984`: Add a `bytes32 indexed memo` field to the `ConfidentialTransfer` event (`amount` is no longer indexed). The internal `_mint`, `_burn`, `_transfer`, `_transferAndCall` and `_update` functions take an additional `bytes32 memo` parameter. Public confidential transfer functions without input proofs have been removed.
