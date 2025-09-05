// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984RwaComplianceModule, IERC7984RwaTransferComplianceModule, TRANSFER_COMPLIANCE_MODULE_TYPE} from "./../../../interfaces/IERC7984Rwa.sol";

/**
 * @dev A contract which allows to build an transfer compliance module for confidential Real World Assets (RWAs).
 */
abstract contract ERC7984RwaTransferComplianceModule is
    IERC7984RwaComplianceModule,
    IERC7984RwaTransferComplianceModule
{
    /// @inheritdoc IERC7984RwaComplianceModule
    function isModuleType(uint256 moduleTypeId) public pure override returns (bool) {
        return moduleTypeId == TRANSFER_COMPLIANCE_MODULE_TYPE;
    }

    /// @inheritdoc IERC7984RwaTransferComplianceModule
    function isCompliantTransfer(address from, address to, euint64 encryptedAmount) public virtual returns (bool) {
        return _isCompliantTransfer(from, to, encryptedAmount);
    }

    function _isCompliantTransfer(address from, address to, euint64 encryptedAmount) internal virtual returns (bool);
}
