---
'openzeppelin-confidential-contracts': minor
---

`ERC7984`, `ERC7984ERC20Wrapper`, `ERC7984Freezable`, `ERC7984Hooked`, `ERC7984ObserverAccess`, `ERC7984Restricted`, `ERC7984Votes`: Add an `operator` argument to `_update`, `_mint`, `_burn`, `_transfer`, `_transferAndCall`, `_wrap` and `_unwrap`. Public functions pass `msg.sender`, `ERC7984ERC20Wrapper.onTransferReceived` passes the ERC-1363 `operator`, and `_unwrap` checks that `operator` is an operator of `from`.
