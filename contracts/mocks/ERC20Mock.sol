// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC1363, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC1363.sol";

contract ERC20Mock is ERC1363 {
    uint8 private immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function $_mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function $_burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
}
