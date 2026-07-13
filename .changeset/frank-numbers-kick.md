---
'openzeppelin-confidential-contracts': minor
---

`ERC7984BalanceCapHookModule` and `ERC7984HolderCapHookModule`: Switch hook manager authentication from agent check to calling `IERC7984Hooked-isHookManager` on the token.
