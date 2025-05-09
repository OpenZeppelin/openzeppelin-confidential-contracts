// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @dev A minimalistic vault managed by the deployer.
contract ManagedVault is Ownable {
    error MangedVaultCallFailed();

    constructor() Ownable(msg.sender) {}

    /// @dev Execute a given call to `to` with value `value` and calldata `data. Only callable by {owner}.
    function call(address to, uint256 value, bytes calldata data) public virtual onlyOwner {
        (bool success, ) = to.call{ value: value }(data);
        require(success, MangedVaultCallFailed());
    }
}
