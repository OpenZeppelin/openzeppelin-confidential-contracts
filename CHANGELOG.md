# openzeppelin-confidential-contracts


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
