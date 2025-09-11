// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC7984RwaTransferComplianceModule} from "./ERC7984RwaTransferComplianceModule.sol";

/**
 * @dev A transfer compliance module for confidential Real World Assets (RWAs) which limits the number of investors.
 */
abstract contract ERC7984RwaInvestorCapModule is ERC7984RwaTransferComplianceModule {
    using EnumerableSet for *;

    uint256 private _maxInvestor;
    EnumerableSet.AddressSet private _investors;

    constructor(address compliance, uint256 maxInvestor) ERC7984RwaTransferComplianceModule(compliance) {
        setMaxInvestor(maxInvestor);
    }

    /// @dev Sets max number of investors.
    function setMaxInvestor(uint256 maxInvestor) public virtual onlyCompliance {
        _maxInvestor = maxInvestor;
    }

    /// @dev Gets max number of investors.
    function getMaxInvestor() public virtual returns (uint256) {
        return _maxInvestor;
    }

    /// @dev Internal function which checks if a transfer is compliant.
    function _isCompliantTransfer(
        address /*from*/,
        address to,
        euint64 encryptedAmount
    ) internal override returns (ebool) {
        if (
            FHE.isInitialized(encryptedAmount) || // no amount
            to == address(0) || // or burning
            _investors.contains(to) || // or already investor
            _investors.length() < _maxInvestor // or not reached max investors limit
        ) {
            return FHE.asEbool(true);
        }
        return FHE.asEbool(false);
    }

    /// @dev Internal function which performs operation after transfer.
    function _postTransfer(address /*from*/, address to, euint64 /*encryptedAmount*/) internal override {
        if (!_investors.contains(to)) {
            _investors.add(to);
        }
    }
}
