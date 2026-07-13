---
'openzeppelin-confidential-contracts': minor
---

`ERC7984BalanceCapHookModule` and `ERC7984HolderCapHookModule`: Switch module manager authentication from agent check to calling `IERC7984Hooked-isModuleManager` on the token.
