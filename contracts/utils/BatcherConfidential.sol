// SPDX-License-Identifier: MIT

import {FHE, externalEuint64, euint64, ebool, euint128} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984ERC20Wrapper} from "../token/ERC7984/extensions/ERC7984ERC20Wrapper.sol";
import {FHESafeMath} from "./../utils/FHESafeMath.sol";

pragma solidity ^0.8.27;

abstract contract BatcherConfidential {
    struct Batch {
        euint64 totalDeposits;
        euint64 unwrapAmount;
        uint64 exchangeRate;
        mapping(address => euint64) deposits;
    }

    ERC7984ERC20Wrapper private immutable _fromToken;
    ERC7984ERC20Wrapper private immutable _toToken;
    mapping(uint256 => Batch) private _batches;
    uint256 private _currentBatchId;

    error BatchDispatched(uint256 batchId);
    error BatchNotFinalized(uint256 batchId);
    error ExchangeRateAlreadySet(uint256 batchId);

    constructor(ERC7984ERC20Wrapper fromToken_, ERC7984ERC20Wrapper toToken_) {
        _fromToken = fromToken_;
        _toToken = toToken_;
        _currentBatchId = 1;
    }

    /// @dev Join the current batch with `externalAmount` and `inputProof`.
    function join(externalEuint64 externalAmount, bytes calldata inputProof) public virtual {
        euint64 amount = FHE.fromExternal(externalAmount, inputProof);
        FHE.allowTransient(amount, address(fromToken()));
        euint64 transferred = fromToken().confidentialTransferFrom(msg.sender, address(this), amount);

        uint256 batchId = currentBatchId();

        euint64 newDeposits = FHE.add(deposits(batchId, msg.sender), transferred);
        euint64 newTotalDeposits = FHE.add(totalDeposits(batchId), transferred);

        FHE.allowThis(newDeposits);
        FHE.allow(newDeposits, msg.sender);

        FHE.allowThis(newTotalDeposits);

        _batches[batchId].deposits[msg.sender] = newDeposits;
        _batches[batchId].totalDeposits = newTotalDeposits;
    }

    /// @dev Claim the `toToken` corresponding to deposit in batch with id `batchId`.
    function claim(uint256 batchId) public virtual {
        require(_batches[batchId].exchangeRate != 0, BatchNotFinalized(batchId));

        euint64 deposit = deposits(batchId, msg.sender);
        _batches[batchId].deposits[msg.sender] = euint64.wrap(0);

        // Max of 18x exchange rate if entire total supply is included. Should probably decrease mantissa.
        // Overflow not possible on mul since `type(uint64).max ** 2 < type(uint128).max`. Div tbd
        euint64 amountToSend = FHE.asEuint64(
            FHE.div(FHE.mul(FHE.asEuint128(deposit), uint128(_batches[batchId].exchangeRate)), uint128(1e18))
        );
        FHE.allowTransient(amountToSend, address(toToken()));

        // we should not assume success here
        toToken().confidentialTransfer(msg.sender, amountToSend);
    }

    /**
     * @dev Cancel the entire deposit made by `msg.sender` in batch with id `batchId`.
     * This can only be called if the batch has not yet been dispatched.
     *
     * NOTE: Developers should consider adding additional restrictions to this function
     * if maintaining confidentiality of deposits is critical to the application.
     */
    function cancel(uint256 batchId) public virtual {
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

    /**
     * @dev Permissionless function to dispatch the current batch. Increments the {currentBatchId}.
     *
     * NOTE: Developers should consider adding additional restrictions to this function
     * if maintaining confidentiality of deposits is critical to the application.
     */
    function dispatchBatch() public virtual {
        uint256 batchId = currentBatchId();
        _currentBatchId++;

        euint64 amountToUnwrap = totalDeposits(batchId);
        _batches[batchId].unwrapAmount = _calculateUnwrapAmount(amountToUnwrap);

        FHE.allowTransient(amountToUnwrap, address(fromToken()));
        fromToken().unwrap(address(this), address(this), amountToUnwrap);
    }

    /**
     * @dev Dispatch batch callback callable by anyone. This function finalizes the unwrap of {fromToken}
     * and calls {_executeRoute} to perform the batch's route.
     */
    function dispatchBatchCallback(
        uint256 batchId,
        uint64 unwrapAmountCleartext,
        bytes calldata decryptionProof
    ) public virtual {
        euint64 unwrapAmount_ = unwrapAmount(batchId);

        // finalize unwrap call will fail if already called by this contract or by anyone else
        (bool success, ) = address(fromToken()).call(
            abi.encodeCall(ERC7984ERC20Wrapper.finalizeUnwrap, (unwrapAmount_, unwrapAmountCleartext, decryptionProof))
        );

        if (!success) {
            // Must validate input since `finalizeUnwrap` request failed
            bytes32[] memory handles = new bytes32[](1);
            handles[0] = euint64.unwrap(unwrapAmount_);

            bytes memory cleartexts = abi.encode(unwrapAmountCleartext);

            FHE.checkSignatures(handles, cleartexts, decryptionProof);
        }

        _executeRoute(batchId, unwrapAmountCleartext);
    }

    /// @dev Batcher from token. Users deposit this token in exchange for {toToken}.
    function fromToken() public view virtual returns (ERC7984ERC20Wrapper) {
        return _fromToken;
    }

    /// @dev Batcher to token. Users receive this token in exchange for their {fromToken} deposits.
    function toToken() public view virtual returns (ERC7984ERC20Wrapper) {
        return _toToken;
    }

    /// @dev The ongoing batch id. New deposits join this batch.
    function currentBatchId() public view virtual returns (uint256) {
        return _currentBatchId;
    }

    /// @dev The amount of {fromToken} unwrapped during {dispatchBatch} for batch with id `batchId`.
    function unwrapAmount(uint256 batchId) public view virtual returns (euint64) {
        return _batches[batchId].unwrapAmount;
    }

    /// @dev The total deposits made in batch with id `batchId`.
    function totalDeposits(uint256 batchId) public view virtual returns (euint64) {
        return _batches[batchId].totalDeposits;
    }

    /// @dev The deposits made by `account` in batch with id `batchId`.
    function deposits(uint256 batchId, address account) public view virtual returns (euint64) {
        return _batches[batchId].deposits[account];
    }

    /// @dev The exchange rate set for batch with id `batchId`.
    function exchangeRate(uint256 batchId) public view virtual returns (uint64) {
        return _batches[batchId].exchangeRate;
    }

    /// @dev Human readable description of what the batcher does.
    function routeDescription() public pure virtual returns (string memory);

    /**
     * @dev Function which is executed by {dispatchBatchCallback} after validation and unwrap finalization. The parameter
     * `amount` is the plaintext amount of the `fromToken` which were unwrapped--to attain the underlying tokens received,
     * evaluate `amount * fromToken().rate()`.
     *
     * This function should set the exchange rate for the given `batchId` by calling {_setExchangeRate}. The exchange rate
     * represents the rate going from {fromToken} to {toToken}--not the underlying tokens.
     *
     * NOTE: {dispatchBatchCallback} (and in turn {_executeRoute}) can be repeatedly called until the exchange rate is set
     * for the batch. If a multi-step route is necessary, only the final step sets the exchange rate.
     */
    function _executeRoute(uint256 batchId, uint256 amount) internal virtual;

    /**
     * @dev Sets the exchange rate for a given `batchId`. The exchange rate represents the rate at which deposits in {fromToken}
     * are converted to {toToken}.
     *
     * WARNING: Do not supply the exchange rate between the two underling non-confidential tokens. Ensure the wrapper {ERC7984ERC20Wrapper-rate}
     * is taken into account.
     */
    function _setExchangeRate(uint256 batchId, uint64 exchangeRate_) internal virtual {
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
