// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TFHE, einput, ebool, euint64, einput} from "fhevm/lib/TFHE.sol";

import {VestingBase} from "./VestingBase.sol";
import {ManagedVault} from "./ManagedVault.sol";
import {ConfidentialFungibleToken} from "../token/ConfidentialFungibleToken.sol";

contract ConfidentialVesting is VestingBase {
    using TFHE for *;

    ConfidentialFungibleToken immutable token;

    constructor(ConfidentialFungibleToken token_) {
        token = token_;
    }

    function _doTransferIn(address from, uint256 amount) internal virtual override returns (uint256) {
        euint64 encryptedAmount = euint64.wrap(amount);
        encryptedAmount.allowTransient(address(token));

        return euint64.unwrap(token.confidentialTransferFrom(from, address(this), encryptedAmount));
    }

    function _doTransferOut(address to, uint256 amount) internal virtual override returns (uint256) {
        return _doTransferOut(address(this), to, amount);
    }

    function _doTransferOut(address from, address to, uint256 amount) internal virtual override returns (uint256) {
        euint64 encryptedAmount = euint64.wrap(amount);
        encryptedAmount.allowTransient(address(token));

        return euint64.unwrap(token.confidentialTransferFrom(from, to, encryptedAmount));
    }

    function _createManagedVault(uint256 streamId) internal virtual override returns (address) {
        address vault = super._createManagedVault(streamId);

        // Set this contract as operator for the vault
        ManagedVault(vault).call(
            address(token),
            0,
            abi.encodeCall(ConfidentialFungibleToken.setOperator, (address(this), type(uint48).max))
        );

        return vault;
    }

    function _mul(uint256 a, uint256 b) internal virtual override returns (uint256) {
        return euint64.unwrap(uint64(a).asEuint64().mul(euint64.wrap(b)));
    }

    function _sub(uint256 a, uint256 b) internal virtual override returns (uint256) {
        return euint64.unwrap(euint64.wrap(a).sub(euint64.wrap(b)));
    }

    function _add(uint256 a, uint256 b) internal virtual override returns (uint256) {
        return euint64.unwrap(euint64.wrap(a).add(euint64.wrap(b)));
    }

    function _min(uint256 a, uint256 b) internal virtual override returns (uint256) {
        return euint64.unwrap(euint64.wrap(a).min(euint64.wrap(b)));
    }

    function _prestore(uint256 a) internal virtual override returns (uint256) {
        euint64.wrap(a).allowThis();
        return a;
    }

    function createVestingStream(
        uint48 startTime,
        address recipient,
        einput totalAmount,
        einput amountPerSecond,
        bytes memory amountInputProof,
        bytes memory amountPerSecondInputProof
    ) public virtual {
        _createVestingStream(
            startTime,
            recipient,
            euint64.unwrap(totalAmount.asEuint64(amountInputProof)),
            euint64.unwrap(amountPerSecond.asEuint64(amountPerSecondInputProof))
        );
    }
}
