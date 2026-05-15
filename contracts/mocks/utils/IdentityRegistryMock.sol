// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

contract IdentityRegistryMock {
    mapping(address => bool) private _verified;

    function setVerified(address user, bool verified) external {
        _verified[user] = verified;
    }

    function isVerified(address user) external view returns (bool) {
        return _verified[user];
    }
}
