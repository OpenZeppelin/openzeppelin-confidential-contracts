// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {FHESafeMath} from "../../utils/FHESafeMath.sol";
import {ConfidentialFungibleToken} from "../ConfidentialFungibleToken.sol";

/**
 * Inspired by https://github.com/OpenZeppelin/openzeppelin-community-contracts/pull/186.
 *
 * @dev Extension of {ERC7984} that allows to implement a freezing
 * mechanism that can be managed by an authorized account with the
 * {_setConfidentialFrozen} function.
 *
 * The freezing mechanism provides the guarantee to the contract owner
 * (e.g. a DAO or a well-configured multisig) that a specific amount
 * of tokens held by an account won't be transferable until those
 * tokens are unfrozen.
 */
abstract contract ERC7984Freezable is ConfidentialFungibleToken {
    /// @dev Frozen amount of tokens per address.
    mapping(address account => euint64 encryptedAmount) private _frozenBalances;

    error ERC7984UnauthorizedUseOfEncryptedAmount(euint64 encryptedAmount, address user);

    event Frozen(address indexed account, euint64 encryptedAmount);

    /// @dev Returns the frozen balance of an account.
    function confidentialFrozen(address account) public view virtual returns (euint64) {
        return _frozenBalances[account];
    }

    /// @dev Returns the available (unfrozen) balance of an account. Up to {confidentialBalanceOf}.
    function confidentialAvailable(address account) public virtual returns (euint64) {
        (ebool success, euint64 unfrozen) = FHESafeMath.tryDecrease(
            confidentialBalanceOf(account),
            confidentialFrozen(account)
        );
        unfrozen = FHE.select(success, unfrozen, FHE.asEuint64(0));
        FHE.allowThis(unfrozen);
        return unfrozen;
    }

    /// @dev Internal function to set the frozen token amount for an account.
    function setConfidentialFrozen(
        address account,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual {
        return setConfidentialFrozen(account, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Internal function to set the frozen token amount for an account.
    function setConfidentialFrozen(address account, euint64 encryptedAmount) public virtual {
        require(
            FHE.isAllowed(encryptedAmount, msg.sender),
            ERC7984UnauthorizedUseOfEncryptedAmount(encryptedAmount, msg.sender)
        );
        return _setConfidentialFrozen(account, encryptedAmount);
    }

    function _setConfidentialFrozen(address account, euint64 encryptedAmount) internal virtual {
        _checkFreezer();
        FHE.allowThis(encryptedAmount);
        FHE.allow(encryptedAmount, account);
        _frozenBalances[account] = encryptedAmount;
        emit Frozen(account, encryptedAmount);
    }

    function _checkFreezer() internal virtual;

    /**
     * @dev See {ERC7984-_update}.
     *
     * Requirements:
     *
     * * `from` must have sufficient unfrozen balance.
     */
    function _update(address from, address to, euint64 encryptedAmount) internal virtual override returns (euint64) {
        if (from != address(0)) {
            euint64 unfrozen = confidentialAvailable(from);
            encryptedAmount = FHE.select(FHE.le(encryptedAmount, unfrozen), encryptedAmount, FHE.asEuint64(0));
        }
        return super._update(from, to, encryptedAmount);
    }

    // We don't check frozen balance for approvals since the actual transfer
    // will be checked in _update. This allows for more flexible approval patterns.
}
