---
'openzeppelin-confidential-contracts': minor
---

`ERC7984`, `ERC7984ERC20Wrapper`, `ERC7984Freezable`, `ERC7984Hooked`, `ERC7984ObserverAccess`, `ERC7984Restricted`, and `ERC7984Votes`: Add a `bypassRestrictions` parameter to the internal `_update`, `_mint`, `_burn`, and `_transfer` functions so extensions can identify and skip additional transfer restrictions for permissioned flows such as refunds and wraps.
