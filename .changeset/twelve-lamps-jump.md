---
'openzeppelin-confidential-contracts': minor
---

`ERC7984ERC20Wrapper`: Track amounts that were paid for but not minted when `_update` caps the confidential total supply, and let holders redeem them through `unwrap` (consumed before burning any confidential balance). The unminted amount of a holder can be read with the new `unmintedAmountOf` getter.
