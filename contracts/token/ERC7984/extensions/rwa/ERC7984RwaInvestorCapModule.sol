// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984} from "../../../../interfaces/IERC7984.sol";
import {ERC7984RwaComplianceModule} from "./ERC7984RwaComplianceModule.sol";

/**
 * @dev A transfer compliance module for confidential Real World Assets (RWAs) which limits the number of investors.
 */
abstract contract ERC7984RwaInvestorCapModule is ERC7984RwaComplianceModule {
    uint64 private _maxInvestor;
    euint64 private _investors;

    event MaxInvestorSet(uint64 maxInvestor);

    constructor(address token, uint64 maxInvestor) ERC7984RwaComplianceModule(token) {
        _maxInvestor = maxInvestor;
    }

    /// @dev Sets max number of investors.
    function setMaxInvestor(uint64 maxInvestor) public virtual onlyTokenAdmin {
        _maxInvestor = maxInvestor;
        emit MaxInvestorSet(maxInvestor);
    }

    /// @dev Gets max number of investors.
    function getMaxInvestor() public view virtual returns (uint64) {
        return _maxInvestor;
    }

    /// @dev Gets current number of investors.
    function getCurrentInvestor() public view virtual returns (euint64) {
        return _investors;
    }

    /// @dev Internal function which checks if a transfer is compliant.
    function _isCompliantTransfer(
        address /*from*/,
        address to,
        euint64 encryptedAmount
    ) internal override returns (ebool compliant) {
        euint64 balance = IERC7984(_token).confidentialBalanceOf(to);
        _getTokenHandleAllowance(balance);
        _getTokenHandleAllowance(encryptedAmount);
        compliant = FHE.or(
            FHE.or(
                FHE.asEbool(to == address(0)), // return true if burning
                FHE.eq(encryptedAmount, FHE.asEuint64(0)) // or zero amount
            ),
            FHE.or(
                FHE.gt(balance, FHE.asEuint64(0)), // or already investor
                FHE.lt(_investors, FHE.asEuint64(_maxInvestor)) // or not reached max investors limit
            )
        );
    }

    /// @dev Internal function which performs operation after transfer.
    function _postTransfer(address /*from*/, address to, euint64 encryptedAmount) internal override {
        euint64 balance = IERC7984(_token).confidentialBalanceOf(to);
        _getTokenHandleAllowance(balance);
        _getTokenHandleAllowance(encryptedAmount);
        if (!FHE.isInitialized(_investors)) {
            _investors = FHE.asEuint64(0);
        }
        _investors = FHE.select(FHE.eq(balance, encryptedAmount), FHE.add(_investors, FHE.asEuint64(1)), _investors);
        _investors = FHE.select(FHE.eq(balance, FHE.asEuint64(0)), FHE.sub(_investors, FHE.asEuint64(1)), _investors);
        FHE.allowThis(_investors);
    }
}
