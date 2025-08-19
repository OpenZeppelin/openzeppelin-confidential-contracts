// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC1363Receiver} from "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ConfidentialFungibleToken} from "./../ConfidentialFungibleToken.sol";

/**
 * @dev Extension of {ConfidentialFungibleToken} that allows each account to add a custodian who is given
 * permanent ACL access to its transfer amounts. A custodian can be added or removed at any point in time.
 */
abstract contract ConfidentialFungibleTokenCustodianAccess is ConfidentialFungibleToken {
    mapping(address => address) private _custodians;

    event ConfidentialFungibleTokenCustodianAccessCustodianSet(
        address account,
        address oldCustodian,
        address newCustodian
    );

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

            emit ConfidentialFungibleTokenCustodianAccessCustodianSet(
                account,
                oldCustodian,
                _custodians[account] = newCustodian
            );
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
            FHE.allow(transferred, fromCustodian);
        }
        if (toCustodian != address(0) && toCustodian != fromCustodian) {
            FHE.allow(transferred, toCustodian);
        }
    }
}
