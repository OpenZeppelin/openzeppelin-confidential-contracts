// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ConfidentialFungibleToken, euint64} from "../ConfidentialFungibleToken.sol";

abstract contract ConfidentialFungibleTokenERC20Like is ConfidentialFungibleToken {
    function _update(address from, address to, euint64 amount) internal virtual override returns (euint64) {
        emit IERC20.Transfer(from, to, 0);
        return super._update(from, to, amount);
    }
}
