// SPDX-License-Identifier: MIT

import {FHE, externalEuint64, euint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984ERC20Wrapper} from "../token/ERC7984/extensions/ERC7984ERC20Wrapper.sol";
import {FHESafeMath} from "./../utils/FHESafeMath.sol";

pragma solidity ^0.8.24;

contract BatcherConfidential {
    ERC7984ERC20Wrapper private _fromToken;
    ERC7984ERC20Wrapper private _toToken;
    mapping(uint256 => Batch) private _batches;
    uint256 private _currentBatchId = 1;

    struct Batch {
        euint64 confidentialAmount;
        euint64 unwrapAmount;
        mapping(address => euint64) deposits;
    }

    constructor(ERC7984ERC20Wrapper fromToken_, ERC7984ERC20Wrapper toToken_) {
        _fromToken = fromToken_;
        _toToken = toToken_;
    }

    function join(externalEuint64 externalAmount, bytes calldata inputProof) public {
        euint64 amount = FHE.fromExternal(externalAmount, inputProof);
        FHE.allowTransient(amount, address(fromToken()));
        euint64 transferred = fromToken().confidentialTransferFrom(msg.sender, address(this), amount);

        euint64 newDeposits = FHE.add(_batches[_currentBatchId].deposits[msg.sender], transferred);
        FHE.allowThis(newDeposits);
        _batches[_currentBatchId].deposits[msg.sender] = newDeposits;

        euint64 newTotalDeposits = FHE.add(_batches[_currentBatchId].confidentialAmount, transferred);
        FHE.allowThis(newTotalDeposits);
        _batches[_currentBatchId].confidentialAmount = newTotalDeposits;
    }

    function exit() public {}

    function dispatchBatch() public {
        uint256 batchId = _currentBatchId++;
        euint64 amountToUnwrap = _batches[batchId].confidentialAmount;
        FHE.allowTransient(amountToUnwrap, address(fromToken()));
        _batches[batchId].unwrapAmount = _calculateUnwrapAmount(amountToUnwrap);
        fromToken().unwrap(address(this), address(this), amountToUnwrap);
    }

    function dispatchBatchCallback(
        uint256 batchId,
        uint64 unwrapAmountCleartext,
        bytes calldata decryptionProof
    ) public {
        euint64 unwrapAmount = _batches[batchId].unwrapAmount;

        // May revert since anyone can finalize on behalf of the contract
        try fromToken().finalizeUnwrap(unwrapAmount, unwrapAmountCleartext, decryptionProof) {} catch {}
    }

    function finalizeBatch() public {}

    function fromToken() public view returns (ERC7984ERC20Wrapper) {
        return _fromToken;
    }

    function toToken() public view returns (ERC7984ERC20Wrapper) {
        return _toToken;
    }

    function batchUnwrapAmount(uint256 batchId) public view returns (euint64) {
        return _batches[batchId].unwrapAmount;
    }

    /// @dev Mirror calculations done on the token to attain the same cipher-text for unwrap tracking.
    function _calculateUnwrapAmount(euint64 requestedUnwrapAmount) private returns (euint64) {
        euint64 balance = fromToken().confidentialBalanceOf(address(this));

        (ebool success, ) = FHESafeMath.tryDecrease(balance, requestedUnwrapAmount);

        return FHE.select(success, requestedUnwrapAmount, FHE.asEuint64(0));
    }
}
