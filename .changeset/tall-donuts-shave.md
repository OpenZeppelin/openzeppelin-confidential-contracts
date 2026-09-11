---
'openzeppelin-confidential-contracts': minor
---

`ERC7984Hooked`: Pass the transfer's `operator` (the `msg.sender` that initiated the update) to the pre- and post-transfer hooks. `IERC7984HookModule.preTransfer` and `IERC7984HookModule.postTransfer` now take an additional leading `operator` argument, and `ERC7984HookModule._preTransfer` / `_postTransfer` receive it after `token`.
