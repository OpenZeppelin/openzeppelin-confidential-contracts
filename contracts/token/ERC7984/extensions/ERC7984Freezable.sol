// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {FHESafeMath} from "../../../utils/FHESafeMath.sol";
import {ERC7984} from "../ERC7984.sol";

/**
 * @dev Extension of {ERC7984} that implements a confidential
 * freezing mechanism that can be managed by an authorized account with
 * {setConfidentialFrozen} functions.
 *
 * The freezing mechanism provides the guarantee to the contract owner
 * (e.g. a DAO or a well-configured multisig) that a specific confidential
 * amount of tokens held by an account won't be transferable until those
 * tokens are unfrozen.
 *
 * Inspired by https://github.com/OpenZeppelin/openzeppelin-community-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Freezable.sol
 */
abstract contract ERC7984Freezable is ERC7984 {
    /// @dev Confidential frozen amount of tokens per address.
    mapping(address account => euint64 encryptedAmount) private _frozenBalances;

    /// @dev Emitted when a confidential amount of token is frozen for an account
    event TokensFrozen(address indexed account, euint64 encryptedAmount);

    /// @dev Returns the confidential frozen balance of an account.
    function confidentialFrozen(address account) public view virtual returns (euint64) {
        return _frozenBalances[account];
    }

    /// @dev Returns the confidential available (unfrozen) balance of an account. Up to {confidentialBalanceOf}.
    function confidentialAvailable(address account) public virtual returns (euint64) {
        (ebool success, euint64 unfrozen) = FHESafeMath.tryDecrease(
            confidentialBalanceOf(account),
            confidentialFrozen(account)
        );
        return FHE.select(success, unfrozen, FHE.asEuint64(0));
    }

    /// @dev Internal function to freeze a confidential amount of tokens for an account.
    function _setConfidentialFrozen(address account, euint64 encryptedAmount) internal virtual {
        _checkFreezer();
        FHE.allowThis(encryptedAmount);
        FHE.allow(encryptedAmount, account);
        _frozenBalances[account] = encryptedAmount;
        emit TokensFrozen(account, encryptedAmount);
    }

    /// @dev Unimplemented function that must revert if `msg.sender` is not authorized as a freezer.
    function _checkFreezer() internal virtual;

    /**
     * @dev See {ERC7984-_update}. The `from` account must have sufficient unfrozen balance,
     * otherwise 0 tokens are transferred.
     */
    function _update(address from, address to, euint64 encryptedAmount) internal virtual override returns (euint64) {
        if (from != address(0)) {
            euint64 unfrozen = confidentialAvailable(from);
            encryptedAmount = FHE.select(FHE.le(encryptedAmount, unfrozen), encryptedAmount, FHE.asEuint64(0));
        }
        return super._update(from, to, encryptedAmount);
    }
}
