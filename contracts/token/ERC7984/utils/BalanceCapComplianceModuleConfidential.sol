// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC7984} from "./../../../interfaces/IERC7984.sol";
import {IERC7984Rwa} from "./../../../interfaces/IERC7984Rwa.sol";
import {FHESafeMath} from "./../../../utils/FHESafeMath.sol";
import {ERC7984HookModule} from "./ERC7984HookModule.sol";

/// @dev A transfer compliance module for confidential Real World Assets (RWAs) which limits the balance of an investor.
abstract contract BalanceCapComplianceModuleConfidential is ERC7984HookModule {
    using EnumerableSet for *;

    event MaxBalanceSet(address token, uint64 newMaxBalance);

    mapping(address => uint64) private _maxBalances;

    function onInstall(bytes calldata initData) public override {
        uint64 maxBalance = abi.decode(initData, (uint64));
        _setMaxBalance(msg.sender, maxBalance);

        super.onInstall(initData);
    }

    /// @dev Sets the max balance for a given token `token` to `maxBalance`.
    function setMaxBalance(address token, uint64 maxBalance) public virtual {
        require(IERC7984Rwa(token).isAgent(msg.sender), "ERC7984HookModule: caller is not an agent");
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

    /// @inheritdoc ERC7984HookModule
    function _preTransfer(
        address token,
        address from,
        address to,
        euint64 encryptedAmount
    ) internal override returns (ebool) {
        if (to == address(0) || from == to) {
            return FHE.asEbool(true);
        }

        euint64 balance = IERC7984(token).confidentialBalanceOf(to);
        _getTokenHandleAllowance(token, balance);

        if (FHE.isInitialized(balance))
            require(FHE.isAllowed(balance, token), ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(balance, token));

        if (FHE.isInitialized(encryptedAmount))
            require(
                FHE.isAllowed(encryptedAmount, token),
                ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(encryptedAmount, token)
            );

        (ebool increased, euint64 futureBalance) = FHESafeMath.tryIncrease(balance, encryptedAmount);
        return FHE.and(increased, FHE.le(futureBalance, maxBalances(token)));
    }
}
