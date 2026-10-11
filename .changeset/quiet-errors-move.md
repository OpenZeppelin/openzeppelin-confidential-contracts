---
'openzeppelin-confidential-contracts': minor
---

`IERC7984ERC20Wrapper`: Declare the `InvalidUnwrapRequest` error, moved from `ERC7984ERC20Wrapper`. `finalizeUnwrap` must revert with it when the unwrap request does not exist or was already finalized.
