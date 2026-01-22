// SPDX-License-Identifier: MIT

import {FHE, externalEuint64, euint64, ebool, euint128} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984ERC20Wrapper} from "../token/ERC7984/extensions/ERC7984ERC20Wrapper.sol";
import {FHESafeMath} from "./../utils/FHESafeMath.sol";

pragma solidity ^0.8.24;

abstract contract BatcherConfidential {
    ERC7984ERC20Wrapper private _fromToken;
    ERC7984ERC20Wrapper private _toToken;
    mapping(uint256 => Batch) private _batches;
    uint256 private _currentBatchId;

    struct Batch {
        euint64 totalDeposits;
        euint64 unwrapAmount;
        uint256 exchangeRate;
        mapping(address => euint64) deposits;
    }

    error BatchNotFinalized(uint256 batchId);
    error ExchangeRateAlreadySet(uint256 batchId);
    error BatchDispatched(uint256 batchId);

    constructor(ERC7984ERC20Wrapper fromToken_, ERC7984ERC20Wrapper toToken_) {
        _fromToken = fromToken_;
        _toToken = toToken_;
        _currentBatchId = 1;
    }

    function join(externalEuint64 externalAmount, bytes calldata inputProof) public virtual {
        euint64 amount = FHE.fromExternal(externalAmount, inputProof);
        FHE.allowTransient(amount, address(fromToken()));
        euint64 transferred = fromToken().confidentialTransferFrom(msg.sender, address(this), amount);

        uint256 batchId = currentBatchId();

        euint64 newDeposits = FHE.add(deposits(batchId, msg.sender), transferred);
        FHE.allowThis(newDeposits);
        FHE.allow(newDeposits, msg.sender);
        _batches[batchId].deposits[msg.sender] = newDeposits;

        euint64 newTotalDeposits = FHE.add(totalDeposits(batchId), transferred);
        FHE.allowThis(newTotalDeposits);
        _batches[batchId].totalDeposits = newTotalDeposits;
    }

    function exit(uint256 batchId) public virtual {
        require(_batches[batchId].exchangeRate != 0, BatchNotFinalized(batchId));

        euint64 deposit = deposits(batchId, msg.sender);
        _batches[batchId].deposits[msg.sender] = euint64.wrap(0);

        // Max of 18x exchange rate if entire total supply is included. Should probably decrease mantissa.
        euint64 amountToSend = FHE.asEuint64(
            FHE.div(FHE.mul(FHE.asEuint128(deposit), uint128(_batches[batchId].exchangeRate)), uint128(1e18))
        );
        FHE.allowTransient(amountToSend, address(toToken()));

        toToken().confidentialTransfer(msg.sender, amountToSend);
    }

    function quit(uint256 batchId) public virtual {
        require(euint64.unwrap(unwrapAmount(batchId)) == 0, BatchDispatched(batchId));

        euint64 deposit = deposits(batchId, msg.sender);
        euint64 totalDeposits_ = totalDeposits(batchId);

        euint64 sent = fromToken().confidentialTransfer(msg.sender, deposit);
        euint64 newDeposit = FHE.sub(deposit, sent);
        euint64 newTotalDeposits = FHE.sub(totalDeposits_, sent);

        FHE.allowThis(newDeposit);
        FHE.allow(newDeposit, msg.sender);

        FHE.allowThis(newTotalDeposits);

        _batches[batchId].deposits[msg.sender] = newDeposit;
        _batches[batchId].totalDeposits = newTotalDeposits;
    }

    function dispatchBatch() public virtual {
        uint256 batchId = currentBatchId();
        _currentBatchId++;

        euint64 amountToUnwrap = totalDeposits(batchId);
        _batches[batchId].unwrapAmount = _calculateUnwrapAmount(amountToUnwrap);

        FHE.allowTransient(amountToUnwrap, address(fromToken()));
        fromToken().unwrap(address(this), address(this), amountToUnwrap);
    }

    function dispatchBatchCallback(
        uint256 batchId,
        uint64 unwrapAmountCleartext,
        bytes calldata decryptionProof
    ) public virtual {
        euint64 unwrapAmount_ = _batches[batchId].unwrapAmount;

        // finalize unwrap call will fail if already called by this contract or by anyone else
        (bool success, ) = address(fromToken()).call(
            abi.encodeCall(ERC7984ERC20Wrapper.finalizeUnwrap, (unwrapAmount_, unwrapAmountCleartext, decryptionProof))
        );

        if (!success) {
            // Must validate input since finalizeUnwrap request failed
            bytes32[] memory handles = new bytes32[](1);
            handles[0] = euint64.unwrap(unwrapAmount_);

            bytes memory cleartexts = abi.encode(unwrapAmountCleartext);

            FHE.checkSignatures(handles, cleartexts, decryptionProof);
        }

        _executeRoute(batchId, unwrapAmountCleartext);
    }

    function fromToken() public view returns (ERC7984ERC20Wrapper) {
        return _fromToken;
    }

    function toToken() public view returns (ERC7984ERC20Wrapper) {
        return _toToken;
    }

    function currentBatchId() public view virtual returns (uint256) {
        return _currentBatchId;
    }

    function unwrapAmount(uint256 batchId) public view returns (euint64) {
        return _batches[batchId].unwrapAmount;
    }

    function totalDeposits(uint256 batchId) public view virtual returns (euint64) {
        return _batches[batchId].totalDeposits;
    }

    function deposits(uint256 batchId, address account) public view virtual returns (euint64) {
        return _batches[batchId].deposits[account];
    }

    function exchangeRate(uint256 batchId) public view virtual returns (uint256) {
        return _batches[batchId].exchangeRate;
    }

    function _executeRoute(uint256 batchId, uint256 amount) internal virtual;

    function _setExchangeRate(uint256 batchId, uint256 exchangeRate_) internal virtual {
        require(exchangeRate(batchId) == 0, ExchangeRateAlreadySet(batchId));
        _batches[batchId].exchangeRate = exchangeRate_;
    }

    /// @dev Mirror calculations done on the token to attain the same cipher-text for unwrap tracking.
    function _calculateUnwrapAmount(euint64 requestedUnwrapAmount) internal virtual returns (euint64) {
        euint64 balance = fromToken().confidentialBalanceOf(address(this));

        (ebool success, ) = FHESafeMath.tryDecrease(balance, requestedUnwrapAmount);

        return FHE.select(success, requestedUnwrapAmount, FHE.asEuint64(0));
    }
}
