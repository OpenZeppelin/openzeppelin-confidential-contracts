// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ConfidentialFungibleToken, euint64} from "../ConfidentialFungibleToken.sol";

/**
 * @dev Extension of `ConfidentialFungibleToken` that emits ERC20 events on transfers. This
 * can be useful for surfacing confidential transfers on applications that support ERC20 events such as Etherscan.
 *
 * NOTE: The ERC20 events emitted only have meaningful data for the `to` and `from` fields. The `amount` field
 * is fixed to 1.
 */
abstract contract ConfidentialFungibleTokenERC20Events is ConfidentialFungibleToken {
    function _update(address from, address to, euint64 amount) internal virtual override returns (euint64) {
        emit IERC20.Transfer(from, to, 1);
        return super._update(from, to, amount);
    }
}
