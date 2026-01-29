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

    mapping(address => euint64) private _maxBalances;

    event MaxBalanceSet(address token, euint64 newMaxBalance);

    /// @dev Sets max balance of an investor with proof.
    function setMaxBalance(
        address token,
        externalEuint64 maxBalance,
        bytes calldata inputProof
    ) public virtual onlyTokenAgent(token) {
        euint64 maxBalance_ = FHE.fromExternal(maxBalance, inputProof);
        FHE.allowThis(_maxBalances[token] = maxBalance_);
        emit MaxBalanceSet(token, maxBalance_);
    }

    /// @dev Gets max balance of an investor.
    function maxBalances(address token) public view virtual returns (euint64) {
        return _maxBalances[token];
    }

    /// @dev Internal function which checks if a transfer is compliant.
    function _isCompliantTransfer(
        address token,
        address from,
        address to,
        euint64 encryptedAmount
    ) internal override returns (ebool) {
        if (to == address(0) || from == to) {
            return FHE.asEbool(true); // if burning or self-transfer
        }

        euint64 balance = IERC7984(token).confidentialBalanceOf(to);
        _getTokenHandleAllowance(token, balance);

        require(FHE.isAllowed(balance, token), UnauthorizedUseOfEncryptedAmount(balance, token));
        require(FHE.isAllowed(encryptedAmount, token), UnauthorizedUseOfEncryptedAmount(encryptedAmount, token));

        (ebool increased, euint64 futureBalance) = FHESafeMath.tryIncrease(balance, encryptedAmount);
        return FHE.and(increased, FHE.le(futureBalance, maxBalances(token)));
    }
}
