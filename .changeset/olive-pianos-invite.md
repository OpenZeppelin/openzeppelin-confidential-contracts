---
'openzeppelin-confidential-contracts': minor
---

`ERC7984`: Add encrypted spending limits to operators. `setOperator` now takes an encrypted `limit` and its input proof, `isOperator` returns the remaining allowance alongside the approval status, and operator-initiated transfers decrement the allowance by the amount actually moved, while a transfer that exceeds the remaining allowance moves nothing. A `limit` handle of `~bytes32(0)` registers an unlimited operator. `ERC7984ERC20Wrapper`: Consume the operator allowance when unwrapping on behalf of a holder.
