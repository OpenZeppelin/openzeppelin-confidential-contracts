// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC7984} from "../../interfaces/IERC7984.sol";
import {FHESafeMath} from "../../utils/FHESafeMath.sol";
import {ComplianceModuleConfidential} from "./ComplianceModuleConfidential.sol";

/// @dev A transfer compliance module for confidential Real World Assets (RWAs) which limits the balance of an investor.
abstract contract BalanceCapComplianceModuleConfidential is ComplianceModuleConfidential {
    using EnumerableSet for *;

    event MaxBalanceSet(address token, uint64 newMaxBalance);

    mapping(address => uint64) private _maxBalances;

    function onInstall(bytes calldata initData) public override {
        uint64 maxBalance = abi.decode(initData, (uint64));
        _setMaxBalance(msg.sender, maxBalance);

        super.onInstall(initData);
    }

    /// @dev Sets the max balance for a given token `token` to `maxBalance`.
    function setMaxBalance(address token, uint64 maxBalance) public virtual onlyTokenAgent(token) {
        _setMaxBalance(token, maxBalance);
    }

    /// @dev Gets max balance for a given token `token`.
    function maxBalances(address token) public view virtual returns (uint64) {
        return _maxBalances[token];
    }

    function _setMaxBalance(address token, uint64 maxBalance) internal {
        _maxBalances[token] = maxBalance;

        emit MaxBalanceSet(token, maxBalance);
    }

    /// @inheritdoc ComplianceModuleConfidential
    function _isCompliantTransfer(
        address token,
        address from,
        address to,
        euint64 encryptedAmount
    ) internal override returns (ebool) {
        if (to == address(0) || from == to) {
            return FHE.allowTransient(FHE.asEbool(true), msg.sender); // if burning or self-transfer
        }

        euint64 balance = IERC7984(token).confidentialBalanceOf(to);
        _getTokenHandleAllowance(token, balance);

        if (FHE.isInitialized(balance))
            require(FHE.isAllowed(balance, token), UnauthorizedUseOfEncryptedAmount(balance, token));

        if (FHE.isInitialized(encryptedAmount))
            require(FHE.isAllowed(encryptedAmount, token), UnauthorizedUseOfEncryptedAmount(encryptedAmount, token));

        (ebool increased, euint64 futureBalance) = FHESafeMath.tryIncrease(balance, encryptedAmount);
        return FHE.and(increased, FHE.le(futureBalance, maxBalances(token)));
    }
}
