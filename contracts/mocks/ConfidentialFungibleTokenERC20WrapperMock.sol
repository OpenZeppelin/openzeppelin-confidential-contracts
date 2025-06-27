// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {ConfidentialFungibleTokenERC20Wrapper, ConfidentialFungibleToken} from "../token/extensions/ConfidentialFungibleTokenERC20Wrapper.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract ConfidentialFungibleTokenERC20WrapperMock is ConfidentialFungibleTokenERC20Wrapper, SepoliaConfig {
    constructor(
        IERC20 token,
        string memory name,
        string memory symbol,
        string memory uri
    ) ConfidentialFungibleTokenERC20Wrapper(token) ConfidentialFungibleToken(name, symbol, uri) {}
}
