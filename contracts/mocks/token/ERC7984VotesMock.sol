// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC7984, ERC7984Votes, VotesConfidential} from "../../token/ERC7984/extensions/ERC7984Votes.sol";
import {ERC7984Mock} from "./ERC7984Mock.sol";

abstract contract ERC7984VotesMock is ERC7984Mock, ERC7984Votes {
    address private immutable _OWNER;

    uint48 private _clockOverrideVal;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory tokenURI_
    ) ERC7984Mock(name_, symbol_, tokenURI_) EIP712(name_, "1.0.0") {
        _OWNER = msg.sender;
    }

    function clock() public view virtual override returns (uint48) {
        if (_clockOverrideVal != 0) {
            return _clockOverrideVal;
        }
        return super.clock();
    }

    function confidentialTotalSupply() public view virtual override(ERC7984, ERC7984Votes) returns (euint64) {
        return super.confidentialTotalSupply();
    }

    function _update(
        address from,
        address to,
        euint64 amount
    ) internal virtual override(ERC7984Mock, ERC7984Votes) returns (euint64) {
        return super._update(from, to, amount);
    }

    function _setClockOverride(uint48 val) external {
        _clockOverrideVal = val;
    }

    function _validateHandleAllowance(bytes32 handle) internal view override {}
}
