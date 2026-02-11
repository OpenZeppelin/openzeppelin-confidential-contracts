// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, externalEuint64, euint64, ebool, euint128} from "@fhevm/solidity/lib/FHE.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC7984Receiver} from "./../interfaces/IERC7984Receiver.sol";
import {ERC7984ERC20Wrapper} from "./../token/ERC7984/extensions/ERC7984ERC20Wrapper.sol";
import {FHESafeMath} from "./../utils/FHESafeMath.sol";

abstract contract BatcherConfidential is ReentrancyGuardTransient, IERC7984Receiver {
    /// @dev Enum representing the lifecycle state of a batch.
    enum BatchState {
        Pending, // Batch is active and accepting deposits (batchId == currentBatchId)
        Dispatched, // Batch has been dispatched but not yet finalized
        Finalized, // Batch is complete, users can claim their tokens
        Canceled // Batch is canceled, users can claim their refund
    }

    struct Batch {
        euint64 totalDeposits;
        euint64 unwrapAmount;
        uint64 totalDepositsCleartext;
        uint64 exchangeRate;
        bool canceled;
        mapping(address => euint64) deposits;
    }

    ERC7984ERC20Wrapper private immutable _fromToken;
    ERC7984ERC20Wrapper private immutable _toToken;
    mapping(uint256 => Batch) private _batches;
    uint256 private _currentBatchId;

    /// @dev Emitted when a batch with id `batchId` is dispatched via {dispatchBatch}.
    event BatchDispatched(uint256 indexed batchId);

    /// @dev Emitted when a batch with id `batchId` is canceled via {_cancel}.
    event BatchCanceled(uint256 indexed batchId);

    /**
     * @dev Emitted when a batch with id `batchId` is finalized via {_setExchangeRate}
     * with an exchange rate of `exchangeRate`.
     */
    event BatchFinalized(uint256 indexed batchId, uint64 exchangeRate);

    /// @dev Emitted when an `account` joins a batch with id `batchId` with a deposit of `amount`.
    event Joined(uint256 indexed batchId, address indexed account, euint64 amount);

    /// @dev Emitted when an `account` claims their `amount` from batch with id `batchId`.
    event Claimed(uint256 indexed batchId, address indexed account, euint64 amount);

    /// @dev Emitted when an `account` quits a batch with id `batchId`.
    event Quit(uint256 indexed batchId, address indexed account, euint64 amount);

    /// @dev The `batchId` does not exist. Batch IDs start at 1 and must be less than or equal to {currentBatchId}.
    error BatchNonexistent(uint256 batchId);

    /**
     * @dev The batch `batchId` is in the state `current`, which is invalid for the operation.
     * The `expectedStates` is a bitmap encoding the expected/allowed states for the operation.
     *
     * See {_encodeStateBitmap}.
     */
    error BatchUnexpectedState(uint256 batchId, BatchState current, bytes32 expectedStates);

    /**
     * @dev Thrown when the given exchange rate is invalid. `exchangeRate * totalDeposits / 10 ** exchangeRateDecimals`
     * must fit in uint64.
     */
    error InvalidExchangeRate(uint256 batchId, uint256 totalDeposits, uint64 exchangeRate);

    constructor(ERC7984ERC20Wrapper fromToken_, ERC7984ERC20Wrapper toToken_) {
        _fromToken = fromToken_;
        _toToken = toToken_;
        _currentBatchId = 1;
    }

    /// @dev Join the current batch with `externalAmount` and `inputProof`.
    function join(externalEuint64 externalAmount, bytes calldata inputProof) public virtual returns (euint64) {
        euint64 amount = FHE.fromExternal(externalAmount, inputProof);
        FHE.allowTransient(amount, address(fromToken()));
        euint64 transferred = fromToken().confidentialTransferFrom(msg.sender, address(this), amount);

        euint64 joinedAmount = _join(msg.sender, transferred);
        euint64 refundAmount = FHE.sub(transferred, joinedAmount);

        FHE.allowTransient(joinedAmount, msg.sender);
        FHE.allowTransient(refundAmount, address(fromToken()));

        fromToken().confidentialTransfer(msg.sender, refundAmount);

        return joinedAmount;
    }

    /// @dev Claim the `toToken` corresponding to deposit in batch with id `batchId`.
    function claim(uint256 batchId) public virtual nonReentrant returns (euint64) {
        _validateStateBitmap(batchId, _encodeStateBitmap(BatchState.Finalized));

        euint64 deposit = deposits(batchId, msg.sender);

        // Overflow is not possible on mul since `type(uint64).max ** 2 < type(uint128).max`.
        // Given that the output of the entire batch must fit in uint64, individual user outputs must also fit.
        euint64 amountToSend = FHE.asEuint64(
            FHE.div(FHE.mul(FHE.asEuint128(deposit), exchangeRate(batchId)), uint128(10) ** exchangeRateDecimals())
        );
        FHE.allowTransient(amountToSend, address(toToken()));

        euint64 amountTransferred = toToken().confidentialTransfer(msg.sender, amountToSend);

        ebool transferSuccess = FHE.eq(amountTransferred, amountToSend);
        euint64 newDeposit = FHE.select(transferSuccess, FHE.asEuint64(0), deposit);

        FHE.allowThis(newDeposit);
        FHE.allow(newDeposit, msg.sender);
        _batches[batchId].deposits[msg.sender] = newDeposit;

        emit Claimed(batchId, msg.sender, amountTransferred);

        return amountTransferred;
    }

    /**
     * @dev Quit the batch with id `batchId`. Entire deposit is returned to the user.
     * This can only be called if the batch has not yet been dispatched or if the batch was canceled.
     *
     * NOTE: Developers should consider adding additional restrictions to this function
     * if maintaining confidentiality of deposits is critical to the application.
     */
    function quit(uint256 batchId) public virtual nonReentrant returns (euint64) {
        _validateStateBitmap(batchId, _encodeStateBitmap(BatchState.Pending) | _encodeStateBitmap(BatchState.Canceled));

        euint64 deposit = deposits(batchId, msg.sender);
        euint64 totalDeposits_ = totalDeposits(batchId);

        FHE.allowTransient(deposit, address(fromToken()));
        euint64 sent = fromToken().confidentialTransfer(msg.sender, deposit);
        euint64 newDeposit = FHE.sub(deposit, sent);
        euint64 newTotalDeposits = FHE.sub(totalDeposits_, sent);

        FHE.allowThis(newDeposit);
        FHE.allow(newDeposit, msg.sender);

        FHE.allowThis(newTotalDeposits);

        _batches[batchId].deposits[msg.sender] = newDeposit;
        _batches[batchId].totalDeposits = newTotalDeposits;

        emit Quit(batchId, msg.sender, sent);

        return sent;
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

        emit BatchDispatched(batchId);
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
        _validateStateBitmap(batchId, _encodeStateBitmap(BatchState.Dispatched));

        euint64 unwrapAmount_ = unwrapAmount(batchId);
        uint64 totalDepositsCleartext_ = totalDepositsCleartext(batchId);

        if (totalDepositsCleartext_ != 0) {
            unwrapAmountCleartext = totalDepositsCleartext_;
        } else {
            // finalize unwrap call will fail if already called by this contract or by anyone else
            (bool success, ) = address(fromToken()).call(
                abi.encodeCall(
                    ERC7984ERC20Wrapper.finalizeUnwrap,
                    (unwrapAmount_, unwrapAmountCleartext, decryptionProof)
                )
            );

            if (!success) {
                // Must validate input since `finalizeUnwrap` request failed
                bytes32[] memory handles = new bytes32[](1);
                handles[0] = euint64.unwrap(unwrapAmount_);

                bytes memory cleartexts = abi.encode(unwrapAmountCleartext);

                FHE.checkSignatures(handles, cleartexts, decryptionProof);
            }

            _batches[batchId].totalDepositsCleartext = unwrapAmountCleartext;
        }

        uint64 exchangeRate_ = _executeRoute(batchId, unwrapAmountCleartext);
        if (exchangeRate_ != 0) {
            _setExchangeRate(batchId, exchangeRate_);
        }
    }

    /// @inheritdoc IERC7984Receiver
    function onConfidentialTransferReceived(
        address operator,
        address from,
        euint64 amount,
        bytes calldata
    ) external returns (ebool) {
        ebool success = FHE.gt(_join(from, amount), FHE.asEuint64(0));
        FHE.allowTransient(success, operator);
        return success;
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

    function totalDepositsCleartext(uint256 batchId) public view virtual returns (uint64) {
        return _batches[batchId].totalDepositsCleartext;
    }

    /// @dev The deposits made by `account` in batch with id `batchId`.
    function deposits(uint256 batchId, address account) public view virtual returns (euint64) {
        return _batches[batchId].deposits[account];
    }

    /// @dev The exchange rate set for batch with id `batchId`.
    function exchangeRate(uint256 batchId) public view virtual returns (uint64) {
        return _batches[batchId].exchangeRate;
    }

    /// @dev The number of decimals of precision for the exchange rate.
    function exchangeRateDecimals() public pure virtual returns (uint8) {
        return 6;
    }

    /// @dev Human readable description of what the batcher does.
    function routeDescription() public pure virtual returns (string memory);

    /// @dev Returns the current state of a batch. Reverts if the batch does not exist.
    function batchState(uint256 batchId) public view virtual returns (BatchState) {
        if (_batches[batchId].canceled) {
            return BatchState.Canceled;
        }
        if (exchangeRate(batchId) != 0) {
            return BatchState.Finalized;
        }
        if (euint64.unwrap(unwrapAmount(batchId)) != 0) {
            return BatchState.Dispatched;
        }
        if (batchId == currentBatchId()) {
            return BatchState.Pending;
        }

        revert BatchNonexistent(batchId);
    }

    /**
     * @dev Joins a batch with amount `amount` on behalf of `to`. Does not do any transfers in.
     * Returns the amount joined with.
     */
    function _join(address to, euint64 amount) internal virtual returns (euint64) {
        uint256 batchId = currentBatchId();

        (ebool success, euint64 newTotalDeposits) = FHESafeMath.tryIncrease(totalDeposits(batchId), amount);
        euint64 joinedAmount = FHE.select(success, amount, FHE.asEuint64(0));
        euint64 newDeposits = FHE.add(deposits(batchId, to), joinedAmount);

        FHE.allowThis(newTotalDeposits);

        FHE.allowThis(newDeposits);
        FHE.allow(newDeposits, to);

        _batches[batchId].totalDeposits = newTotalDeposits;
        _batches[batchId].deposits[to] = newDeposits;

        emit Joined(batchId, to, joinedAmount);

        return joinedAmount;
    }

    /**
     * @dev Function which is executed by {dispatchBatchCallback} after validation and unwrap finalization. The parameter
     * `amount` is the plaintext amount of the `fromToken` which were unwrapped--to attain the underlying tokens received,
     * evaluate `amount * fromToken().rate()`.
     *
     * This function returns the exchange rate for the given `batchId`. The exchange rate
     * represents the rate going from {fromToken} to {toToken}--not the underlying tokens.
     * If the exchange rate is not ready, 0 should be returned.
     *
     * NOTE: {dispatchBatchCallback} (and in turn {_executeRoute}) can be repeatedly called until the exchange rate returned
     * as a non-zero value. If a multi-step route is necessary, only the final returns a non-zero value.
     *
     * WARNING: This function must eventually return a non-zero value. Failure to do so results in user deposits being
     * locked indefinitely.
     */
    function _executeRoute(uint256 batchId, uint256 amount) internal virtual returns (uint64);

    /**
     * @dev Cancels a batch with id `batchId`. A canceled batch can be exited by calling {quit}.
     *
     * NOTE: This function should be extended to implement additional logic which retrieves the batch assets
     * and rewraps them for quitting users.
     */
    function _cancel(uint256 batchId) internal virtual {
        _validateStateBitmap(
            batchId,
            _encodeStateBitmap(BatchState.Pending) | _encodeStateBitmap(BatchState.Dispatched)
        );

        _batches[batchId].canceled = true;

        emit BatchCanceled(batchId);
    }

    /**
     * @dev Check that the current state of a batch matches the requirements described by the `allowedStates` bitmap.
     * This bitmap should be built using `_encodeStateBitmap`.
     *
     * If requirements are not met, reverts with a {BatchUnexpectedState} error.
     */
    function _validateStateBitmap(uint256 batchId, bytes32 allowedStates) internal view returns (BatchState) {
        BatchState currentState = batchState(batchId);
        if (_encodeStateBitmap(currentState) & allowedStates == bytes32(0)) {
            revert BatchUnexpectedState(batchId, currentState, allowedStates);
        }
        return currentState;
    }

    /**
     * @dev Sets the exchange rate for a given `batchId`. The exchange rate represents the rate at which deposits in {fromToken} are
     * converted to {toToken}. The exchange rate is scaled by `10 ** exchangeRateDecimals()`. An exchange rate of 0 is invalid.
     *
     * WARNING: Do not supply the exchange rate between the two underlying non-confidential tokens. Ensure the wrapper {ERC7984ERC20Wrapper-rate}
     * is taken into account.
     */
    function _setExchangeRate(uint256 batchId, uint64 exchangeRate_) internal virtual {
        _validateStateBitmap(batchId, _encodeStateBitmap(BatchState.Dispatched));
        uint256 totalDepositsCleartext_ = totalDepositsCleartext(batchId);

        // Ensure valid exchange rate: not 0 and will not overflow when calculating user outputs
        require(
            exchangeRate_ != 0 &&
                (totalDepositsCleartext_ * exchangeRate_) / (uint128(10) ** exchangeRateDecimals()) <= type(uint64).max,
            InvalidExchangeRate(batchId, totalDepositsCleartext_, exchangeRate_)
        );

        _batches[batchId].exchangeRate = exchangeRate_;

        emit BatchFinalized(batchId, exchangeRate_);
    }

    /// @dev Mirror calculations done on the token to attain the same cipher-text for unwrap tracking.
    function _calculateUnwrapAmount(euint64 requestedUnwrapAmount) internal virtual returns (euint64) {
        euint64 balance = fromToken().confidentialBalanceOf(address(this));

        (ebool success, ) = FHESafeMath.tryDecrease(balance, requestedUnwrapAmount);

        return FHE.select(success, requestedUnwrapAmount, FHE.asEuint64(0));
    }

    /**
     * @dev Encodes a `BatchState` into a `bytes32` representation where each bit enabled corresponds to
     * the underlying position in the `BatchState` enum. For example:
     *
     * 0x000...1000
     *         ^--- Canceled
     *          ^-- Finalized
     *           ^- Dispatched
     *            ^ Pending
     */
    function _encodeStateBitmap(BatchState batchState_) internal pure returns (bytes32) {
        return bytes32(1 << uint8(batchState_));
    }
}
