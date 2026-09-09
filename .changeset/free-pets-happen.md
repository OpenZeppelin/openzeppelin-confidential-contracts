---
'openzeppelin-confidential-contracts': minor
---

`ERC7984ERC20Wrapper`: Allow developers to associate 12 bytes of metadata with an unwrap request. This gets packed into the storage slot that is already being used to store the unwrap request recipient. Note that the internal `_unwrap` function signature changed to accept an additional `bytes12 unwrapMetadata` parameter, so contracts overriding `_unwrap` must update their signature accordingly.
