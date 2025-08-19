// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.2.0) (token/extensions/ConfidentialFungibleTokenVotes.sol)
pragma solidity ^0.8.27;

import {euint64} from "@fhevm/solidity/lib/FHE.sol";
import {VotesConfidential} from "../../../governance/utils/VotesConfidential.sol";
import {ERC7984} from "./../ERC7984.sol";

/**
 * @dev Extension of {ERC7984} supporting confidential votes tracking and delegation.
 *
 * The amount of confidential voting units an account has is equal to the balance of
 * that account. Voing power is taken into account when an account delegates votes to itself or to another
 * account.
 */
abstract contract ERC7984Votes is ERC7984, VotesConfidential {
    /// @inheritdoc ERC7984
    function confidentialTotalSupply() public view virtual override(VotesConfidential, ERC7984) returns (euint64) {
        return super.confidentialTotalSupply();
    }

    function _update(address from, address to, euint64 amount) internal virtual override returns (euint64 transferred) {
        transferred = super._update(from, to, amount);

        _transferVotingUnits(from, to, transferred);
    }

    function _getVotingUnits(address account) internal view virtual override returns (euint64) {
        return confidentialBalanceOf(account);
    }
}
