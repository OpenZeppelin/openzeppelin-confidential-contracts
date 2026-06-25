---
'openzeppelin-confidential-contracts': minor
---

`ERC7984BalanceCapHookModule` and `ERC7984HolderCapHookModule`: Switch configurator authentication from agent check to calling `IERC7984Hooked-isAuthorizedConfigurator` on the token.
