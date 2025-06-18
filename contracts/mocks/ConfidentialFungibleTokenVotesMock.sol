// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TFHE, euint64, einput} from "fhevm/lib/TFHE.sol";
import {SepoliaZamaFHEVMConfig} from "fhevm/config/ZamaFHEVMConfig.sol";
import {ConfidentialFungibleTokenVotes, ConfidentialFungibleToken} from "../token/extensions/ConfidentialFungibleTokenVotes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

abstract contract ConfidentialFungibleTokenVotesMock is ConfidentialFungibleTokenVotes, SepoliaZamaFHEVMConfig {
    address private immutable _OWNER;

    uint48 private _clockOverrideVal;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory tokenURI_
    ) ConfidentialFungibleToken(name_, symbol_, tokenURI_) EIP712(name_, "1.0.0") {
        _OWNER = msg.sender;
    }

    // solhint-disable-next-line func-name-mixedcase
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
