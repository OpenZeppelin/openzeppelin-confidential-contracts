// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC7984ERC20WrapperMock} from "./ERC7984ERC20WrapperMock.sol";

/**
 * @dev Wrapper mock that disables the synchronous total-supply overflow check, so `_update` silently caps the minted
 * amount (returning less than requested) instead of reverting. This makes the unminted-amount bookkeeping observable.
 */
contract ERC7984ERC20WrapperUncheckedSupplyMock is ERC7984ERC20WrapperMock {
    constructor(
        IERC20 token,
        string memory name,
        string memory symbol,
        string memory uri
    ) ERC7984ERC20WrapperMock(token, name, symbol, uri) {}

    function _checkConfidentialTotalSupply() internal override {}
}
