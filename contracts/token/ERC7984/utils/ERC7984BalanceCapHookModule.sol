// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.5.0) (token/ERC7984/utils/ERC7984BalanceCapHookModule.sol)

pragma solidity ^0.8.27;

import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984Rwa} from "./../../../interfaces/IERC7984Rwa.sol";
import {FHESafeMath} from "./../../../utils/FHESafeMath.sol";
import {ERC7984HookModule} from "./ERC7984HookModule.sol";

/**
 * @dev An ERC-7984 hook module that limits the balance of each investor.
 *
 * The cap is stored as an encrypted `euint64` value. The pre-transfer hook compares the recipient's prospective balance to the
 * encrypted cap and emits an encrypted compliance result via {ERC7984HookModule-_emitPreTransferResults}.
 *
 * This module is compatible with {ERC7984Hooked}.
 *
 * WARNING: This module notifies senders of the result of the pre-transfer hook. This can be used to leak
 * information about the balance of the recipient. This is a potential security risk and should be used
 * with caution. Production use-cases may want to remove this notification.
 */
contract ERC7984BalanceCapHookModule is ERC7984HookModule {
    /// @dev Emitted when the max balance for a given token is set.
    event ERC7984BalanceCapHookModuleMaxBalanceSet(address indexed token, euint64 newMaxBalance);

    mapping(address => euint64) private _maxBalances;

    /**
     * @dev Sets the max balance for a given token `token` to the encrypted value `newMaxBalance`.
     *
     * `msg.sender` must have the agent role on `token`.
     */
    function setMaxBalance(address token, externalEuint64 newMaxBalance, bytes calldata inputProof) public virtual {
        require(IERC7984Rwa(token).isAgent(msg.sender), ERC7984HookModuleUnauthorizedAccount(msg.sender));
        _setMaxBalance(token, FHE.fromExternal(newMaxBalance, inputProof));
    }

    /// @dev Gets the encrypted max balance for a given token `token`. Returns the zero handle if unset.
    function maxBalance(address token) public view virtual returns (euint64) {
        return _maxBalances[token];
    }

    /// @dev Sets the encrypted max balance for a given token, grants the module persistent ACL, and emits an event.
    function _setMaxBalance(address token, euint64 newMaxBalance) internal virtual {
        newMaxBalance = FHE.allowThis(newMaxBalance);
        newMaxBalance = FHE.allow(newMaxBalance, msg.sender);
        _maxBalances[token] = newMaxBalance;

        emit ERC7984BalanceCapHookModuleMaxBalanceSet(token, newMaxBalance);
    }

    /// @inheritdoc ERC7984HookModule
    function _preTransfer(
        address token,
        address from,
        address to,
        euint64 encryptedAmount
    ) internal override returns (ebool result) {
        // super call
        result = super._preTransfer(token, from, to, encryptedAmount);

        // in non trivial cases, check (and document) compliance.
        if (to != address(0) && to != from && FHE.isInitialized(maxBalance(token))) {
            euint64 balance = IERC7984Rwa(token).confidentialBalanceOf(to);
            _accessHandle(token, balance);

            // Note, if the balance would result in an overflow, transfer will fail due to total supply overflow.
            (, euint64 futureBalance) = FHESafeMath.tryIncrease(balance, encryptedAmount);
            ebool compliant = FHE.le(futureBalance, maxBalance(token));
            _emitPreTransferResults(token, from, to, encryptedAmount, compliant, bytes32(0));

            // integrate this module compliance result into the super result.
            result = FHE.and(result, compliant);
        }
    }

    /**
     * @dev See {ERC7984HookModule-_onInstall}. The `initData` must contain the initial max balance for the token
     * along with the input proof for the max balance. These are encoded using standard ABI encoding.
     */
    function _onInstall(address token, bytes calldata initData) internal virtual override {
        super._onInstall(token, initData);
        (externalEuint64 maxBalance_, bytes memory inputProof) = abi.decode(initData, (externalEuint64, bytes));
        _setMaxBalance(token, FHE.fromExternal(maxBalance_, inputProof));
    }
}
