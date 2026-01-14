// SPDX-License-Identifier: MIT

import {FHE, externalEuint64, euint64, ebool, euint128} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984ERC20Wrapper} from "../token/ERC7984/extensions/ERC7984ERC20Wrapper.sol";
import {FHESafeMath} from "./../utils/FHESafeMath.sol";

pragma solidity ^0.8.24;

abstract contract BatcherConfidential {
    ERC7984ERC20Wrapper private _fromToken;
    ERC7984ERC20Wrapper private _toToken;
    mapping(uint256 => Batch) private _batches;
    uint256 private _currentBatchId = 1;

    struct Batch {
        euint64 amountFromToken;
        euint64 unwrapAmount;
        uint256 exchangeRate;
        mapping(address => euint64) deposits;
    }

    error BatchNotFinalized();

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

        euint64 newTotalDeposits = FHE.add(_batches[_currentBatchId].amountFromToken, transferred);
        FHE.allowThis(newTotalDeposits);
        _batches[_currentBatchId].amountFromToken = newTotalDeposits;
    }

    function exit(uint256 batchId) public {
        require(_batches[batchId].exchangeRate != 0, BatchNotFinalized());

        euint64 deposit = _batches[batchId].deposits[msg.sender];
        _batches[batchId].deposits[msg.sender] = euint64.wrap(0);

        euint128 amountToSend = FHE.div(
            FHE.mul(FHE.asEuint128(deposit), uint128(_batches[batchId].exchangeRate)),
            uint128(1e18)
        );
        toToken().confidentialTransfer(msg.sender, FHE.asEuint64(amountToSend));
    }

    function dispatchBatch() public {
        uint256 batchId = _currentBatchId++;
        euint64 amountToUnwrap = _batches[batchId].amountFromToken;
        _batches[batchId].unwrapAmount = _calculateUnwrapAmount(amountToUnwrap);

        FHE.allowTransient(amountToUnwrap, address(fromToken()));
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

        bytes32[] memory handles = new bytes32[](1);
        handles[0] = euint64.unwrap(unwrapAmount);

        bytes memory cleartexts = abi.encode(unwrapAmountCleartext);

        FHE.checkSignatures(handles, cleartexts, decryptionProof);

        _executeRoute(unwrapAmountCleartext);
    }

    function finalizeBatch() public {
        // _executeRoute();
    }

    function fromToken() public view returns (ERC7984ERC20Wrapper) {
        return _fromToken;
    }

    function toToken() public view returns (ERC7984ERC20Wrapper) {
        return _toToken;
    }

    function batchUnwrapAmount(uint256 batchId) public view returns (euint64) {
        return _batches[batchId].unwrapAmount;
    }

    function _executeRoute(uint256 amount) internal virtual;

    /// @dev Mirror calculations done on the token to attain the same cipher-text for unwrap tracking.
    function _calculateUnwrapAmount(euint64 requestedUnwrapAmount) private returns (euint64) {
        euint64 balance = fromToken().confidentialBalanceOf(address(this));

        (ebool success, ) = FHESafeMath.tryDecrease(balance, requestedUnwrapAmount);

        return FHE.select(success, requestedUnwrapAmount, FHE.asEuint64(0));
    }
}
