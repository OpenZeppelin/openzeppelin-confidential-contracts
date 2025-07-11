# openzeppelin-confidential-contracts


## 0.2.0-rc.1 (2025-07-11)

- `VestingWalletConfidential`: A vesting wallet that releases confidential tokens owned by it according to a defined vesting schedule. ([#99](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/99))
  `VestingWalletCliffConfidential`: A variant of `VestingWalletConfidential` which adds a cliff period to the vesting schedule.
  `VestingWalletExecutorConfidential`: A variant of `VestingWalletConfidential` which allows a trusted executor to execute arbitrary calls from the vesting wallet.

- `IConfidentialFungibleToken`: Prefix `totalSupply` and `balanceOf` functions with confidential. ([#99](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/99))
- `ERC7821WithExecutor`: Add an abstract contract that inherits from `ERC7821` and adds an `executor` role.
- `ConfidentialFungibleTokenERC20Wrapper`: Add an internal function to allow overriding the maximum decimals value. ([#99](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/99))
- `VestingWalletCliffExecutorConfidentialFactory`: Fund multiple `VestingWalletCliffExecutorConfidential` in batch.

## 0.2.0-rc.0 (2025-07-04)

- Upgrade all contracts to use `@fhevm/solidity` 0.7.0. ([#77](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/77))
- `ConfidentialFungibleToken`: Change the default decimals from 9 to 6. ([#74](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/74))
- `ConfidentialFungibleTokenVotes`: Add an extension of `ConfidentialFungibleToken` that implements `VotesConfidential`. ([#40](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/40))
- `CheckpointsConfidential`: Add a library for handling checkpoints with confidential value types. ([#77](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/77))
- `VotesConfidential`: Add votes governance utility for keeping track of FHE vote delegations. ([#40](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts/pull/40))
