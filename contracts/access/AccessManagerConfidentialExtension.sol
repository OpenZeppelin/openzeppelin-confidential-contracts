// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IACL, Impl} from "@fhevm/solidity/lib/Impl.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {RelayedCall} from "@openzeppelin/contracts/utils/RelayedCall.sol";

contract AccessManagerConfidentialExtension is AccessManager {
    constructor(address initialAdmin) AccessManager(initialAdmin) {}

    function getHandlerForRole(uint64 roleId) public returns (address) {
        return RelayedCall.getRelayer(_roleToSalt(roleId));
    }

    function grantDecryptionDelegationAfterDelay(uint64 roleId, address account) public virtual {
        (bool isMember, ) = hasRole(roleId, account);
        require(!isMember, AccessManagerUnauthorizedAccount(account, roleId));
        _delegateDecryption(roleId, account);
    }

    function _grantRole(
        uint64 roleId,
        address account,
        uint32 grantDelay,
        uint32 executionDelay
    ) internal virtual override returns (bool) {
        bool result = super._grantRole(roleId, account, grantDelay, executionDelay);
        if (result && grantDelay == 0) {
            _delegateDecryption(roleId, account);
        }
        return result;
    }

    function _revokeRole(uint64 roleId, address account) internal virtual override returns (bool) {
        bool result = super._revokeRole(roleId, account);
        if (result) {
            _undelegateDecryption(roleId, account);
        }
        return result;
    }

    function _delegateDecryption(uint64 roleId, address account) internal virtual {
        (bool success, bytes memory returndata) = RelayedCall.relayCall(
            Impl.getCoprocessorConfig().ACLAddress,
            abi.encodeCall(IACL.delegateForUserDecryption, (account, address(0), type(uint64).max)), // TODO: address(0) => all contracts
            _roleToSalt(roleId)
        );
        Address.verifyCallResult(success, returndata);
    }

    function _undelegateDecryption(uint64 roleId, address account) internal virtual {
        (bool success, bytes memory returndata) = RelayedCall.relayCall(
            Impl.getCoprocessorConfig().ACLAddress,
            abi.encodeCall(IACL.revokeDelegationForUserDecryption, (account, address(0))), // TODO: address(0) => all contracts
            _roleToSalt(roleId)
        );
        Address.verifyCallResult(success, returndata);
    }

    function _roleToSalt(uint64 roleId) internal view virtual returns (bytes32) {
        require(roleId != PUBLIC_ROLE, AccessManagerLockedRole(roleId));
        return bytes32(uint256(roleId));
    }
}
