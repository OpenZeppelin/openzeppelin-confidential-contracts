// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ManagedVault is Ownable {
    constructor() Ownable(msg.sender) {}

    function call(address to, uint256 value, bytes calldata data) public virtual onlyOwner {
        (bool success, ) = to.call{ value: value }(data);
        require(success, "Call failed");
    }
}
