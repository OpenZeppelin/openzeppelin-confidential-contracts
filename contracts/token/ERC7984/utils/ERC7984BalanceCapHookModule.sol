// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984Rwa} from "./../../../interfaces/IERC7984Rwa.sol";
import {FHESafeMath} from "./../../../utils/FHESafeMath.sol";
import {ERC7984HookModule} from "./ERC7984HookModule.sol";

/**
 * @dev An ERC-7984 hook module that limits the balance of each investor.
 *
 * The cap is stored as an encrypted `euint64` value. While installed but before any cap has been set,
 * the module behaves as default-open (no enforcement). Once {setMaxBalance} is called, the pre-transfer
 * hook compares the recipient's prospective balance to the encrypted cap and emits an encrypted
 * compliance result via {ERC7984HookModule-_emitPreTransferResults}, decryptable only by the sender.
 *
 * NOTE: The cap cannot be supplied during installation. The fhevm input proof is bound to the contract
 * whose frame calls `FHE.fromExternal`; during {ERC7984Hooked-installModule}, that frame is reached
 * with `msg.sender == token`, and the token contract has no key to sign such a proof. Agents must
 * therefore call {setMaxBalance} directly on this module after installation.
 *
 * This module is compatible with {ERC7984Hooked}.
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
        _maxBalances[token] = newMaxBalance;
        FHE.allowThis(newMaxBalance);
        FHE.allow(newMaxBalance, msg.sender);

        emit ERC7984BalanceCapHookModuleMaxBalanceSet(token, newMaxBalance);
    }

    /// @inheritdoc ERC7984HookModule
    function _preTransfer(
        address token,
        address from,
        address to,
        euint64 encryptedAmount
    ) internal override returns (ebool compliant) {
        if (to == address(0) || from == to || !FHE.isInitialized(maxBalance(token))) {
            compliant = FHE.asEbool(true);
        } else {
            euint64 balance = IERC7984Rwa(token).confidentialBalanceOf(to);
            _accessHandle(token, balance);

            (ebool increased, euint64 futureBalance) = FHESafeMath.tryIncrease(balance, encryptedAmount);
            compliant = FHE.and(increased, FHE.le(futureBalance, maxBalance(token)));
        }

        _emitPreTransferResults(token, from, to, encryptedAmount, compliant);
    }

    /// @inheritdoc ERC7984HookModule
    function _onUninstall(address token, bytes calldata deinitData) internal virtual override {
        super._onUninstall(token, deinitData);
        _maxBalances[token] = euint64.wrap(0);
    }
}
