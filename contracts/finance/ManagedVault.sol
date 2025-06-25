// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @dev A minimalistic vault permanently managed by the deployer.
contract ManagedVault {
    address private immutable _owner;

    /// @dev The account `account` is unauthorized to manipulate this vault.
    error MangedVaultUnauthorizedAccount(address account);

    constructor() {
        _owner = msg.sender;
    }

    /// @dev Execute a given call to `to` with value `value` and calldata `data`. Only callable by {owner}.
    function call(address to, uint256 value, bytes calldata data) public virtual {
        require(msg.sender == owner(), MangedVaultUnauthorizedAccount(msg.sender));

        (bool success, bytes memory res) = to.call{value: value}(data);
        Address.verifyCallResult(success, res);
    }

    /// @dev Returns the address of the account owner.
    function owner() public view virtual returns (address) {
        return _owner;
    }
}
