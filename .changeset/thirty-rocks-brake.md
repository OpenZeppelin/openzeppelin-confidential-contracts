---
'openzeppelin-confidential-contracts': minor
---

`ERC7984`, `ERC7984ERC20Wrapper`, `ERC7984Freezable`, `ERC7984Hooked`, `ERC7984ObserverAccess`, `ERC7984Restricted`, and `ERC7984Votes`: Add a `bypassRestrictions` parameter to the internal `_update` function so extensions can identify and skip additional transfer restrictions for permissioned flows such as refunds and wraps. An `_update` overload without the parameter is provided for the common case.
