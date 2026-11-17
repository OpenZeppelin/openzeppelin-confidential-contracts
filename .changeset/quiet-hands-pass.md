---
'openzeppelin-confidential-contracts': minor
---

`ERC7984`, `ERC7984ERC20Wrapper`, `ERC7984Freezable`, `ERC7984Hooked`, `ERC7984ObserverAccess`, `ERC7984Restricted`, `ERC7984Votes`: Add an `operator` argument to `_update`, `_mint`, `_burn`, `_transfer`, `_transferAndCall`, `_wrap` and `_unwrap`. Public functions pass `msg.sender` and `ERC7984ERC20Wrapper.onTransferReceived` passes the ERC-1363 `operator`. `_unwrap` no longer checks that the caller is authorized for `from`; the check moved to the public `unwrap` functions.