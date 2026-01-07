# openzeppelin-confidential-contracts


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
- `ERC7984Freezable`: Add an extension to `ERC7984`, which allows accounts granted the "freezer" role to freeze and unfreeze tokens. ([#151](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/151))
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
