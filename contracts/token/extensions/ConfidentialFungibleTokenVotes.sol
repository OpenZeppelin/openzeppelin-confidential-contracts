// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.2.0-rc.0) (token/extensions/ConfidentialFungibleTokenVotes.sol)
pragma solidity ^0.8.24;

import {euint64} from "@fhevm/solidity/lib/FHE.sol";
import {VotesConfidential} from "./../../governance/utils/VotesConfidential.sol";
import {ConfidentialFungibleToken} from "./../ConfidentialFungibleToken.sol";

abstract contract ConfidentialFungibleTokenVotes is ConfidentialFungibleToken, VotesConfidential {
    function confidentialTotalSupply()
        public
        view
        virtual
        override(VotesConfidential, ConfidentialFungibleToken)
        returns (euint64)
    {
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
