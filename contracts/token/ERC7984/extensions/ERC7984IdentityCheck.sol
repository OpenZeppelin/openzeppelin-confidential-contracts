// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984} from "../ERC7984.sol";

/**
 * @dev Extension of {ERC7984} that enforces identity verification
 * on token recipients by querying an external identity registry.
 *
 * See https://github.com/ERC-3643/ERC-3643/blob/main/contracts/registry/interface/IIdentityRegistry.sol[IIdentityRegistry]
 * for more information.
 */
abstract contract ERC7984IdentityCheck is ERC7984 {
    address private immutable _identityRegistry;

    /// @dev The provided registry address is invalid.
    error ERC7984InvalidIdentityRegistry(address registry);

    /// @dev The `account` is not verified in the identity registry.
    error ERC7984InvalidIdentity(address account);

    constructor(address identityRegistry_) {
        require(
            identityRegistry_ != address(0) && identityRegistry_.code.length != 0,
            ERC7984InvalidIdentityRegistry(identityRegistry_)
        );
        _identityRegistry = identityRegistry_;
    }

    /// @dev See {ERC7984-_update}. Performs identity check before updating the balance.
    function _update(address from, address to, euint64 amount) internal virtual override returns (euint64) {
        if (to != address(0) && !IIdentityRegistry(_identityRegistry).isVerified(to)) {
            revert ERC7984InvalidIdentity(to);
        }
        return super._update(from, to, amount);
    }

    /// @dev Returns the address of the identity registry.
    function identityRegistry() public view returns (address) {
        return _identityRegistry;
    }
}

interface IIdentityRegistry {
    function isVerified(address user) external view returns (bool);
}
