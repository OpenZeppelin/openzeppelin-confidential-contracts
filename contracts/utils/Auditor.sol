// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {FHE} from "@fhevm/solidity/lib/FHE.sol";

/**
 * @dev A contract that allows for the addition and removal of auditors to the ACL. Auditors
 * have the ability to decrypt all handles the granting contract is allowed to decrypt. Auditors
 * do not have the ability to operate on this encrypted data.
 */
abstract contract Auditor {
    address private immutable _WILDCARD_DELEGATION_ADDRESS = address(type(uint160).max);

    /// @dev Add an auditor to the ACL. The auditor remains until explicitly revoked by calling {_removeAuditor}.
    function _addAuditor(address auditor) internal virtual {
        FHE.delegateUserDecryptionWithoutExpiration(auditor, _WILDCARD_DELEGATION_ADDRESS);
    }

    /// @dev Remove an auditor from the ACL. The auditor must have previously been added by calling {_addAuditor}.
    function _removeAuditor(address auditor) internal virtual {
        FHE.revokeUserDecryptionDelegation(auditor, _WILDCARD_DELEGATION_ADDRESS);
    }
}
