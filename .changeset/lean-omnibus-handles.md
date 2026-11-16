---
'openzeppelin-confidential-contracts': minor
---

`ERC7984Omnibus`: Remove the omnibus transfer functions that take existing `eaddress` and `euint64` handles, along with the `ERC7984UnauthorizedUseOfEncryptedAddress` error. Existing handles can be passed to the remaining functions with an empty input proof.
