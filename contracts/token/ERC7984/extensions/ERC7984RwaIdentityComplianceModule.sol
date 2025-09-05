// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IERC7984RwaComplianceModule, IERC7984RwaIdentityComplianceModule, IDENTITY_COMPLIANCE_MODULE_TYPE} from "./../../../interfaces/IERC7984Rwa.sol";

/**
 * @dev A contract which allows to build an identity compliance module for confidential Real World Assets (RWAs).
 */
abstract contract ERC7984RwaIdentityComplianceModule is
    IERC7984RwaComplianceModule,
    IERC7984RwaIdentityComplianceModule
{
    /// @inheritdoc IERC7984RwaComplianceModule
    function isModuleType(uint256 moduleTypeId) public pure override returns (bool) {
        return moduleTypeId == IDENTITY_COMPLIANCE_MODULE_TYPE;
    }

    /// @inheritdoc IERC7984RwaIdentityComplianceModule
    function isCompliantIdentity(address identity) public virtual returns (bool) {
        return _isCompliantIdentity(identity);
    }

    function _isCompliantIdentity(address identity) internal virtual returns (bool);
}
