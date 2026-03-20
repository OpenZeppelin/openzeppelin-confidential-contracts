// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984Rwa} from "./../../../interfaces/IERC7984Rwa.sol";
import {FHESafeMath} from "./../../../utils/FHESafeMath.sol";
import {ERC7984HookModule} from "./ERC7984HookModule.sol";

/// @dev A transfer compliance module for confidential Real World Assets (RWAs) which limits the balance of an investor.
abstract contract ERC7984BalanceCapHookModule is ERC7984HookModule {
    event MaxBalanceSet(address token, uint64 newMaxBalance);

    error Unauthorized();

    mapping(address => uint64) private _maxBalances;

    function onInstall(bytes calldata initData) public override {
        uint64 maxBalance_ = abi.decode(initData, (uint64));
        _setMaxBalance(msg.sender, maxBalance_);

        super.onInstall(initData);
    }

    /// @dev Sets the max balance for a given token `token` to `maxBalance_`.
    function setMaxBalance(address token, uint64 maxBalance_) public virtual {
        require(IERC7984Rwa(token).isAgent(msg.sender), Unauthorized());
        _setMaxBalance(token, maxBalance_);
    }

    /// @dev Gets max balance for a given token `token`.
    function maxBalance(address token) public view virtual returns (uint64) {
        return _maxBalances[token];
    }

    /**
     * @dev Sets the enforced max balance for a given token to `maxBalance`.
     *
     * `msg.sender` must have the agent role on `token`.
     */
    function _setMaxBalance(address token, uint64 maxBalance_) internal {
        _maxBalances[token] = maxBalance_;

        emit MaxBalanceSet(token, maxBalance_);
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

        euint64 balance = IERC7984Rwa(token).confidentialBalanceOf(to);
        _getTokenHandleAllowance(token, balance);

        if (FHE.isInitialized(balance))
            require(FHE.isAllowed(balance, token), ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(balance, token));

        (ebool increased, euint64 futureBalance) = FHESafeMath.tryIncrease(balance, encryptedAmount);
        return FHE.and(increased, FHE.le(futureBalance, maxBalance(token)));
    }
}
