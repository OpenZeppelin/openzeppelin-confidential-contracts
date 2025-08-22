// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984} from "../ERC7984.sol";

/**
 * @dev Extension of {ERC7984} that allows each account to add a observer who is given
 * permanent ACL access to its transfer and balance amounts. A observer can be added or removed at any point in time.
 */
abstract contract ERC7984ObserverAccess is ERC7984 {
    mapping(address => address) private _observers;

    /// @dev Emitted when the observer is changed for the given account `account`.
    event ERC7984ObserverAccessObserverSet(address account, address oldObserver, address newObserver);

    /// @dev Thrown when an account tries to set a `newObserver` for a given `account` without proper authority.
    error Unauthorized();

    /**
     * @dev Sets the observer for the given account `account` to `newObserver`. Can be called by the
     * account or the existing observer to abdicate the observer role (may only set to `address(0)`).
     */
    function setObserver(address account, address newObserver) public virtual {
        address oldObserver = observer(account);
        require(msg.sender == account || (msg.sender == oldObserver && newObserver == address(0)), Unauthorized());
        if (oldObserver != newObserver) {
            if (newObserver != address(0)) {
                euint64 balanceHandle = confidentialBalanceOf(account);
                if (FHE.isInitialized(balanceHandle)) {
                    FHE.allow(balanceHandle, newObserver);
                }
            }

            emit ERC7984ObserverAccessObserverSet(account, oldObserver, _observers[account] = newObserver);
        }
    }

    /// @dev Returns the observer for the given account `account`.
    function observer(address account) public view virtual returns (address) {
        return _observers[account];
    }

    function _update(address from, address to, euint64 amount) internal virtual override returns (euint64 transferred) {
        transferred = super._update(from, to, amount);

        address fromObserver = observer(from);
        address toObserver = observer(to);

        if (fromObserver != address(0)) {
            FHE.allow(confidentialBalanceOf(from), fromObserver);
            FHE.allow(transferred, fromObserver);
        }
        if (toObserver != address(0)) {
            FHE.allow(confidentialBalanceOf(to), toObserver);
            if (toObserver != fromObserver) {
                FHE.allow(transferred, toObserver);
            }
        }
    }
}
