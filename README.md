# <img src="logo.svg" alt="OpenZeppelin" height="40px">

[![Coverage Status](https://codecov.io/gh/OpenZeppelin/openzeppelin-confidential-contracts/graph/badge.svg?token=1OVLRTWTA9)](https://codecov.io/gh/OpenZeppelin/openzeppelin-confidential-contracts)

**An experimental library for developing on the Zama fhEVM**

## Overview

This library contains contracts and utilities that utilize the novel features of the Zama fhEVM coprocessor. Contracts take advantage of the FHE (Fully Homomorphic Encryption) capabilities of the coprocessor to perform confidential transactions. See the [documentation](https://docs.openzeppelin.com/confidential-contracts) and the [Zama documentation](https://docs.zama.ai/protocol) for more details.

### Installation

#### Hardhat (npm)

```
$ npm install @openzeppelin/confidential-contracts
```
→ Installs the latest audited release

### Usage

Once installed, you can use the contracts in the library by importing them:

```solidity
pragma solidity ^0.8.27;

import {ERC7984} from "@openzeppelin/confidential-contracts/token/ERC7984/ERC7984.sol";

abstract contract MyToken is ERC7984 {
    constructor() ERC7984("MyToken", "MTN", "<CONTRACT-URI>") {
    }
}
```

> [!NOTE]
> All contracts built using confidentiality must set the coprocessor configuration. This can be done by inheriting a config file such as `ZamaEthereumConfig`.

> [!WARNING]
> Developing contracts for confidentiality requires extreme care--many functions do not revert on failure as they would in normal contracts.

## Contribute

OpenZeppelin Confidential Contracts exists thanks to its contributors. There are many ways you can participate and help build high quality software. Check out the [contribution guide](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/CONTRIBUTING.md)! This repository follows the same engineering guidelines as [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/GUIDELINES.md).

## License

Each contract file should have their own licence specified. In the absence of any specific licence information, file is released under the [MIT License](LICENSE).

## Legal

Your use of this Project is governed by the terms found at www.openzeppelin.com/tos (the "Terms").
