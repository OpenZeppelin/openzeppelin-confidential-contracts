// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TFHE, euint64, einput } from "fhevm/lib/TFHE.sol";
import { SepoliaZamaFHEVMConfig } from "fhevm/config/ZamaFHEVMConfig.sol";
import { ConfidentialFungibleTokenVotes } from "../token/extensions/ConfidentialFungibleTokenVotes.sol";
import { CheckpointConfidential } from "../utils/structs/CheckpointConfidential.sol";

abstract contract ConfidentialFungibleTokenVotesMock is ConfidentialFungibleTokenVotes, SepoliaZamaFHEVMConfig {
    using CheckpointConfidential for CheckpointConfidential.TraceEuint64;

    address private immutable _OWNER;

    uint48 private _clockOverrideVal;

    constructor() {
        _OWNER = msg.sender;
    }

    function $_mint(
        address to,
        einput encryptedAmount,
        bytes calldata inputProof
    ) public returns (euint64 transferred) {
        return _mint(to, TFHE.asEuint64(encryptedAmount, inputProof));
    }

    function _update(address from, address to, euint64 amount) internal virtual override returns (euint64 transferred) {
        transferred = super._update(from, to, amount);

        TFHE.allow(getCurrentTotalSupply(), _OWNER);
    }

    function _setClockOverride(uint48 val) external {
        _clockOverrideVal = val;
    }

    function clock() public view virtual override returns (uint48) {
        if (_clockOverrideVal != 0) {
            return _clockOverrideVal;
        }
        return super.clock();
    }
}
