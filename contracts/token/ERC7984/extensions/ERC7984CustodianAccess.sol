// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984} from "../ERC7984.sol";

/**
 * @dev Extension of {ERC7984} that allows each account to add a custodian who is given
 * permanent ACL access to its transfer and balance amounts. A custodian can be added or removed at any point in time.
 */
abstract contract ERC7984CustodianAccess is ERC7984 {
    mapping(address => address) private _custodians;

    event ERC7984CustodianAccessCustodianSet(address account, address oldCustodian, address newCustodian);

    error Unauthorized();

    /**
     * @dev Sets the custodian for the given account `account` to `newCustodian`. Can be called by the
     * account or the existing custodian to abdicate the custodian role (may only set to `address(0)`).
     */
    function setCustodian(address account, address newCustodian) public virtual {
        address oldCustodian = custodian(account);
        require(msg.sender == account || (msg.sender == oldCustodian && newCustodian == address(0)), Unauthorized());
        if (oldCustodian != newCustodian) {
            if (newCustodian != address(0)) {
                euint64 balanceHandle = confidentialBalanceOf(account);
                if (FHE.isInitialized(balanceHandle)) {
                    FHE.allow(balanceHandle, newCustodian);
                }
            }

            emit ERC7984CustodianAccessCustodianSet(account, oldCustodian, _custodians[account] = newCustodian);
        }
    }

    /// @dev Returns the custodian for the given account `account`.
    function custodian(address account) public view virtual returns (address) {
        return _custodians[account];
    }

    function _update(address from, address to, euint64 amount) internal virtual override returns (euint64 transferred) {
        transferred = super._update(from, to, amount);

        address fromCustodian = custodian(from);
        address toCustodian = custodian(to);

        if (fromCustodian != address(0)) {
            FHE.allow(confidentialBalanceOf(from), fromCustodian);
            FHE.allow(transferred, fromCustodian);
        }
        if (toCustodian != address(0)) {
            FHE.allow(confidentialBalanceOf(to), toCustodian);
            if (toCustodian != fromCustodian) {
                FHE.allow(transferred, toCustodian);
            }
        }
    }
}
