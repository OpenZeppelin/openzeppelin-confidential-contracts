# openzeppelin-confidential-contracts


## 0.5.3 (2026-08-10)

- `BatcherConfidential`: Extract logic from `quit` into internal function `_quit`. Developers can now call `_quit(batchId, address)` from a derived contract to quit on behalf of a depositor. ([#435](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/435))

## 0.5.2 (2026-08-04)

- `VestingWalletConfidential`: Ensure that tokens are allowed to access handles they return (or the handle is uninitialized). ([#423](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/423))
- `ERC7984`: Check that `IERC7984Receiver` has ACL access to the ebool they return (or the handle is uninitialized). ([#428](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/428))

## 0.5.1 (2026-06-22)

- `BatcherConfidential`: Initialize the zero value before unwrapping when dispatching a batch with no contributions.

## 0.5.0 (2026-06-17)

### Token

- `ERC7984`: Remove revert on transfer where the sender has an uninitialized balance. ([#357](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/357))
- `ERC7984Hooked`: Add an `ERC7984` extension that calls external hooks before and after transfer of confidential tokens. ([#332](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/332))
- `ERC7984HookModule`: Add a base hook module for building modules compatible with `ERC7984Hooked`. ([#351](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/351))
- `ERC7984BalanceCapHookModule`: Add an example hook module that enforces a confidential balance cap for the token. ([#351](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/351))
- `ERC7984HolderCapHookModule`: Add an example hook module that enforces a maximum number of holders for the token. ([#351](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/351))
- `ERC7984Rwa`: Always call `_update` on transfers (even force). Bypass restriction via restriction override. ([#339](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/339))
- `ERC7984Rwa`: Add token recovery functionality. ([#341](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/341))
- `ERC7984Rwa`: Bypass recipient on RWA force transfer in addition to sender. ([#372](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/372))
- `ERC7984Rwa`: Block overrides of `Context` functions (`_msgSender()`, `_msgData()`). ([#382](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/382))
- `IERC7984Rwa`: Add token recovery function and event. ([#341](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/341))

### Finance

- `BatcherConfidential`: Revert if underlying `toToken` balance changes during a partial route execution. ([#385](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/385))

### Utils

- `FHESafeMath`: Add `saturatingAdd` and `saturatingSub` functions. ([#341](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/341))
- `HandleAccessManager`: Return false by default in `_validateHandleAllowance`. ([#338](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/338))

## 0.4.1 (2026-06-08)

### Bug Fixes

- `BatcherConfidential`: Enable decryption of the `joinedAmount` in `BatcherConfidential`. ([#387](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/387))

## 0.4.0 (2026-03-20)

- Migrate `@fhevm/solidity` dependency to `0.11.1` ([#311](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/311))
- Upgrade openzeppelin/contracts and openzeppelin/contracts-upgradeable to v5.6.1 ([#314](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/314))

### Token

- `ERC7984ERC20Wrapper`: use a bytes32 unwrap request identifier instead of identifying batches by the euint64 unwrap amount. ([#326](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/326))
- `ERC7984ERC20Wrapper`: Support ERC-165 interface detection on `ERC7984ERC20Wrapper`. ([#267](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/267))
- `ERC7984ERC20Wrapper`: return the amount of wrapped token sent on wrap calls. ([#307](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/307))
- `ERC7984ERC20Wrapper`: return unwrapped amount on `unwrap` calls ([#288](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/288))
- `ERC7984ERC20Wrapper`: revert on wrap if there is a chance of total supply overflow. ([#268](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/268))
- `ERC7984Restricted`, `ERC7984Rwa`: Rename `isUserAllowed` to `canTransact` ([#291](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/291))

### Finance

- `BatcherConfidential`: A batching primitive that enables routing between two `ERC7984ERC20Wrapper` contracts via a non-confidential route. ([#293](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/293))

### Utils

- `HandleAccessManager`: change `_validateHandleAllowance` to return a boolean and validate it. ([#303](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/303))

## 0.3.1 (2026-01-06)

### Bug fixes

- `ERC7984ERC20Wrapper`: revert on wrap if there is a chance of total supply overflow. ([#268](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/268))

## 0.3.0 (2025-11-28)

- Migrate `@fhevm/solidity` from v0.7.0 to 0.9.1 ([#202](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/202), [#248](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/248), [#254](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/254))

### Token

- Rename all `ConfidentialFungibleToken` files and contracts to use `ERC7984` instead. ([#158](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/158))
- `ERC7984`: Change `tokenURI()` to `contractURI()` following change in the ERC. ([#209](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/209))
- `ERC7984`: Support ERC-165 interface detection on ERC-7984. ([#246](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/246))
- `IERC7984`: Change `tokenURI()` to `contractURI()` following change in the ERC. ([#209](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/209))
- `IERC7984`: Support ERC-165 interface detection on ERC-7984. ([#246](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/246))
- `ERC7984Omnibus`: Add an extension of `ERC7984` that exposes new functions for transferring between confidential subaccounts on omnibus wallets. ([#186](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/186))
- `ERC7984ObserverAccess`: Add an extension for ERC7984, which allows each account to add an observer who is given access to their transfer and balance amounts. ([#148](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/148))
- `ERC7984Restricted`: An extension of `ERC7984` that implements user account transfer restrictions. ([#182](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/182))
- `ERC7984Freezable`: Add an extension to `ERC7984` that implements internal functions with the ability to freeze/unfreeze user tokens. ([#151](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/151))
- `ERC7984Rwa`: An extension of `ERC7984`, that supports confidential Real World Assets (RWAs). ([#160](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/160))

### Utils

- `FHESafeMath`: Add `tryAdd` and `trySub` functions that return 0 upon failure. ([#206](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/206))
- `FHESafeMath`: Support non-initialized inputs in `tryIncrease(..)`/`tryDecrease(..)`. ([#183](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/183))

## 0.2.0 (2025-08-14)

- Upgrade all contracts to use `@fhevm/solidity` 0.7.0. ([#27](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/27))

### Token

- `IConfidentialFungibleToken`: Prefix `totalSupply` and `balanceOf` functions with confidential. ([#93](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/93))
- `IConfidentialFungibleToken`: Rename `EncryptedAmountDisclosed` event to `AmountDisclosed`. ([#93](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/93))
- `ConfidentialFungibleToken`: Change the default decimals from 9 to 6. ([#74](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/74))
- `ConfidentialFungibleTokenERC20Wrapper`: Add an internal function to allow overriding the max decimals used for wrapped tokens. ([#89](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/89))
- `ConfidentialFungibleTokenERC20Wrapper`: Add an internal function to allow overriding the underlying decimals fallback value. ([#133](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/133))

### Governance

- `VotesConfidential`: Add votes governance utility for keeping track of FHE vote delegations. ([#40](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/40))
- `ConfidentialFungibleTokenVotes`: Add an extension of `ConfidentialFungibleToken` that implements `VotesConfidential`. ([#40](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/40))

### Finance

- `VestingWalletConfidential`: A vesting wallet that releases confidential tokens owned by it according to a defined vesting schedule. ([#91](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/91))
- `VestingWalletCliffConfidential`: A variant of `VestingWalletConfidential` which adds a cliff period to the vesting schedule. ([#91](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/91))
- `VestingWalletConfidentialFactory`: A generalized factory that allows for batch funding of confidential vesting wallets. ([#102](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/102))

### Misc

- `HandleAccessManager`: Minimal contract that adds a function to give allowance to callers for a given ciphertext handle. ([#143](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/143))
- `ERC7821WithExecutor`: Add an abstract contract that inherits from `ERC7821` and adds an `executor` role. ([#102](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/102))
- `CheckpointsConfidential`: Add a library for handling checkpoints with confidential value types. ([#60](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/60))
- `TFHESafeMath`: Renamed to `FHESafeMath`. ([#137](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/137))
