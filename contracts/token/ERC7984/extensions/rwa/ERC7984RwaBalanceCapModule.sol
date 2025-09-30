// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC7984} from "../../../../interfaces/IERC7984.sol";
import {FHESafeMath} from "../../../../utils/FHESafeMath.sol";
import {ERC7984RwaComplianceModule} from "./ERC7984RwaComplianceModule.sol";

/**
 * @dev A transfer compliance module for confidential Real World Assets (RWAs) which limits the balance of an investor.
 */
abstract contract ERC7984RwaBalanceCapModule is ERC7984RwaComplianceModule {
    using EnumerableSet for *;

    euint64 private _maxBalance;

    event MaxBalanceSet(euint64 newMaxBalance);

    constructor(address token) ERC7984RwaComplianceModule(token) {
        _token = token;
    }

    /// @dev Sets max balance of an investor with proof.
    function setMaxBalance(externalEuint64 maxBalance, bytes calldata inputProof) public virtual onlyTokenAdmin {
        euint64 maxBalance_ = FHE.fromExternal(maxBalance, inputProof);
        FHE.allowThis(_maxBalance = maxBalance_);
        emit MaxBalanceSet(maxBalance_);
    }

    /// @dev Sets max balance of an investor.
    function setMaxBalance(euint64 maxBalance) public virtual onlyTokenAdmin {
        FHE.allowThis(_maxBalance = maxBalance);
        emit MaxBalanceSet(maxBalance);
    }

    /// @dev Gets max balance of an investor.
    function getMaxBalance() public view virtual returns (euint64) {
        return _maxBalance;
    }

    /// @dev Internal function which checks if a transfer is compliant.
    function _isCompliantTransfer(
        address /*from*/,
        address to,
        euint64 encryptedAmount
    ) internal override returns (ebool compliant) {
        if (to == address(0)) {
            return FHE.asEbool(true); // if burning
        }
        euint64 balance = IERC7984(_token).confidentialBalanceOf(to);
        _getTokenHandleAllowance(balance);
        _getTokenHandleAllowance(encryptedAmount);
        (ebool increased, euint64 futureBalance) = FHESafeMath.tryIncrease(balance, encryptedAmount);
        compliant = FHE.and(increased, FHE.le(futureBalance, _maxBalance));
    }
}
