---
'openzeppelin-confidential-contracts': minor
---

`ERC7984`: Revert in `_setOperator` when the holder is set as its own operator. A holder always has unrestricted access to its own tokens, and that cannot be restricted.
