// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC7984RwaTransferComplianceModule} from "./../../../../interfaces/IERC7984Rwa.sol";
/**
 * @dev A contract which allows to build a transfer compliance module for confidential Real World Assets (RWAs).
 */
abstract contract ERC7984RwaTransferComplianceModule is IERC7984RwaTransferComplianceModule, Ownable {
    /// @dev Throws if called by any account other than the compliance.
    modifier onlyCompliance() {
        _checkOwner();
        _;
    }

    constructor(address compliance) Ownable(compliance) {}

    /// @inheritdoc IERC7984RwaTransferComplianceModule
    function isModule() public pure override returns (bytes4) {
        return this.isModule.selector;
    }

    /// @inheritdoc IERC7984RwaTransferComplianceModule
    function isCompliantTransfer(address from, address to, euint64 encryptedAmount) public virtual returns (ebool) {
        return _isCompliantTransfer(from, to, encryptedAmount);
    }

    /// @inheritdoc IERC7984RwaTransferComplianceModule
    function postTransfer(address from, address to, euint64 encryptedAmount) public virtual {
        _postTransfer(from, to, encryptedAmount);
    }

    /// @dev Internal function which checks if a transfer is compliant.
    function _isCompliantTransfer(
        address /*from*/,
        address /*to*/,
        euint64 /*encryptedAmount*/
    ) internal virtual returns (ebool) {
        // default to non-compliant
        return FHE.asEbool(false);
    }

    /// @dev Internal function which Performs operation after transfer.
    function _postTransfer(address /*from*/, address /*to*/, euint64 /*encryptedAmount*/) internal virtual {
        // default to no-op
    }
}
