# openzeppelin-confidential-contracts


## 0.2.0-rc.2 (2025-07-14)

- `VestingWalletCliffExecutorConfidentialFactory`: Renamed to `VestingWalletConfidentialFactory` and default implementation removed in favor of a user-defined vesting wallet implementation. ([#109](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/109))

## 0.2.0-rc.1 (2025-07-12)

- `VestingWalletConfidential`: A vesting wallet that releases confidential tokens owned by it according to a defined vesting schedule. ([#91](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/91))
- `VestingWalletCliffConfidential`: A variant of `VestingWalletConfidential` which adds a cliff period to the vesting schedule. ([#91](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/91))
- `VestingWalletCliffExecutorConfidentialFactory`: Fund multiple `VestingWalletCliffExecutorConfidential` in batch. ([#102](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/102))
- `ERC7821WithExecutor`: Add an abstract contract that inherits from `ERC7821` and adds an `executor` role. ([#102](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/102))
- `IConfidentialFungibleToken`: Prefix `totalSupply` and `balanceOf` functions with confidential and change `EncryptedAmountDisclosed` event to `AmountDisclosed`. ([#93](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/93))
- `ConfidentialFungibleToken`: Update `totalSupply`, `balanceOf`, and `EncryptedAmountDisclosed` as required by interface changes. ([#93](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/93))
- `ConfidentialFungibleTokenERC20Wrapper`: Add an internal function to allow overriding the maximum decimals value. ([#89](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/89))

## 0.2.0-rc.0 (2025-07-04)

- Upgrade all contracts to use `@fhevm/solidity` 0.7.0. ([#27](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/27))
- `ConfidentialFungibleToken`: Change the default decimals from 9 to 6. ([#74](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/74))
- `ConfidentialFungibleTokenVotes`: Add an extension of `ConfidentialFungibleToken` that implements `VotesConfidential`. ([#40](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/40))
- `VotesConfidential`: Add votes governance utility for keeping track of FHE vote delegations. ([#40](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/40))
- `CheckpointsConfidential`: Add a library for handling checkpoints with confidential value types. ([#60](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/60))
