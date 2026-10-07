// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.5.3) (finance/BatcherConfidential.sol)

pragma solidity ^0.8.26;

import {FHE, externalEuint64, euint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC7984ERC20Wrapper} from "./../interfaces/IERC7984ERC20Wrapper.sol";
import {IERC7984Receiver} from "./../interfaces/IERC7984Receiver.sol";
import {FHESafeMath} from "./../utils/FHESafeMath.sol";

/**
 * @dev `BatcherConfidential` is a batching primitive that enables routing between two {ERC7984ERC20Wrapper} contracts
 * (with distinct underlying tokens) via a non-confidential route. Users deposit {fromToken} into the batcher and receive
 * {toToken} in exchange. Deposits are made by using `ERC7984` transfer and call functions such as {ERC7984-confidentialTransferAndCall}.
 *
 * A batch goes through the following lifecycle:
 *
 * - `Pending`: the current batch accepts deposits, and depositors can {quit}.
 * - `Dispatched`: {dispatchBatch} requested the unwrap of the batch's deposits.
 * - {dispatchBatchCallback} finalizes the unwrap and runs {_executeRoute} once, in the same transaction:
 *   ** if the route reverts, the unwrapped {fromToken} is rewrapped and the batch becomes `Failed`. Depositors can
 *      {quit}, and anyone can dispatch the batch again with {redispatchBatch}.
 *   ** if the route receives its outcome in that call, the batch is finalized.
 *   ** otherwise the route has sent the input to an external service and the batch becomes `Settling`. {settleBatch}
 *      runs {_settleRoute} until the outcome is received, then finalizes the batch.
 * - `Finalized`: the batcher wraps the whole underlying balance of both tokens it holds and pins an {exchangeRate}
 *   ({toToken} per deposited {fromToken}) and a {refundRate} ({fromToken} returned per deposited {fromToken}).
 *   {claim} pays depositors in both tokens.
 *
 * Finalizing on both balances means a route never has to decide whether its outcome is a fill or a refund. An
 * external service may fill the batch, return its input, or do both partially, and anyone may send either underlying
 * token to the batcher: whatever the batcher holds when the batch finalizes goes to that batch's depositors.
 *
 * The underlying tokens the batcher holds belong to the batch in flight. At most one batch is `Dispatched` or
 * `Settling` at a time, and a route must either spend the batch's whole input or revert, so no batch's input is
 * held in the clear across transactions. Dust left after wrapping (less than one wrapped unit) goes to the next
 * finalized batch.
 *
 * Developers must implement {_executeRoute}, {_settleRoute} and {routeDescription}.
 *
 * Claim outputs are rounded down. This may result in small deposits being rounded down to 0 if a rate is less than 1:1.
 *
 * NOTE: The batcher does not support {ERC7984ERC20Wrapper} contracts prior to v0.4.0.
 *
 * NOTE: The batcher could be used to maintain confidentiality of deposits--by default there are no confidentiality guarantees.
 * If desired, developers should consider restricting certain functions to increase confidentiality. Each dispatch
 * publicly decrypts the batch total, so a batch that is dispatched again after depositors {quit} reveals the amount
 * they withdrew.
 *
 * WARNING: The {toToken} and {fromToken} must be carefully inspected to ensure proper capacity is maintained. If {toToken} or
 * {fromToken} are filled--resulting in denial of service--batches could get bricked. The batcher would be unable to wrap
 * underlying tokens when finalizing a batch or rewrapping the input of a failed route.
 */
abstract contract BatcherConfidential is ReentrancyGuardTransient, IERC7984Receiver {
    /// @dev Enum representing the lifecycle state of a batch.
    enum BatchState {
        Pending, // Batch is active and accepting deposits (batchId == currentBatchId)
        Dispatched, // Unwrap of the batch's deposits is requested, the route has not run yet
        Settling, // The route sent the batch's input to an external service, the outcome is not received yet
        Finalized, // The outcome is received, users can claim both tokens
        Failed // The route failed and the input is rewrapped, users can quit or the batch can be dispatched again
    }

    struct Batch {
        euint64 totalDeposits;
        bytes32 unwrapRequestId;
        uint64 unwrapAmount;
        uint64 exchangeRate;
        uint64 refundRate;
        BatchState state;
        mapping(address => euint64) deposits;
    }

    IERC7984ERC20Wrapper private immutable _fromToken;
    IERC7984ERC20Wrapper private immutable _toToken;
    mapping(uint256 => Batch) private _batches;
    uint256 private _currentBatchId;
    uint256 private _inFlightBatchId;

    /// @dev Emitted when a batch with id `batchId` is dispatched via {dispatchBatch} or {redispatchBatch}.
    event BatchDispatched(uint256 indexed batchId);

    /// @dev Emitted when the route of batch `batchId` sent its input to an external service.
    event BatchSettling(uint256 indexed batchId);

    /// @dev Emitted when the route of batch `batchId` reverted and its input was rewrapped.
    event BatchFailed(uint256 indexed batchId, bytes reason);

    /// @dev Emitted when a batch with id `batchId` is finalized with an `exchangeRate` and a `refundRate`.
    event BatchFinalized(uint256 indexed batchId, uint64 exchangeRate, uint64 refundRate);

    /// @dev Emitted when an `account` joins a batch with id `batchId` with a deposit of `amount`.
    event Joined(uint256 indexed batchId, address indexed account, euint64 amount);

    /// @dev Emitted when an `account` claims `toTokenAmount` and `fromTokenAmount` from batch with id `batchId`.
    event Claimed(uint256 indexed batchId, address indexed account, euint64 toTokenAmount, euint64 fromTokenAmount);

    /// @dev Emitted when an `account` quits a batch with id `batchId`.
    event Quit(uint256 indexed batchId, address indexed account, euint64 amount);

    /// @dev The `batchId` does not exist. Batch IDs start at 1 and must be less than or equal to {currentBatchId}.
    error BatchNonexistent(uint256 batchId);

    /// @dev The `account` has a zero deposits in batch `batchId`.
    error ZeroDeposits(uint256 batchId, address account);

    /**
     * @dev The batch `batchId` is in the state `current`, which is invalid for the operation.
     * The `expectedStates` is a bitmap encoding the expected/allowed states for the operation.
     *
     * See {_encodeStateBitmap}.
     */
    error BatchUnexpectedState(uint256 batchId, BatchState current, bytes32 expectedStates);

    /// @dev Batch `batchId` is `Dispatched` or `Settling`. Only one batch can be in flight at a time.
    error BatchInFlight(uint256 batchId);

    /**
     * @dev Thrown when the rates of a finalized batch are invalid: at least one of them must be non-zero, and the
     * wrapped amount of each token must be less than or equal to `type(uint64).max`.
     */
    error InvalidExchangeRate(uint256 batchId, uint256 totalDeposits, uint64 exchangeRate, uint64 refundRate);

    /// @dev The route of batch `batchId` neither spent the batch's whole input nor received its outcome.
    error UnspentInput(uint256 batchId);

    /// @dev Intermediate steps must not transfer underlying {toToken} or {fromToken} into the batcher.
    error IntermediateStepBalanceChanged(uint256 batchId);

    /// @dev The route of batch `batchId` ran out of gas. The callback must be retried with more gas.
    error InsufficientRouteGas(uint256 batchId);

    /// @dev The caller is not authorized to call this function.
    error Unauthorized();

    /// @dev The given `token` does not support `IERC7984ERC20Wrapper` via `ERC165`.
    error InvalidWrapperToken(address token);

    /// @dev The underlying wrapper tokens are the same.
    error DuplicateUnderlyingTokens();

    constructor(IERC7984ERC20Wrapper fromToken_, IERC7984ERC20Wrapper toToken_) {
        require(
            ERC165Checker.supportsInterface(address(fromToken_), type(IERC7984ERC20Wrapper).interfaceId),
            InvalidWrapperToken(address(fromToken_))
        );
        require(
            ERC165Checker.supportsInterface(address(toToken_), type(IERC7984ERC20Wrapper).interfaceId),
            InvalidWrapperToken(address(toToken_))
        );
        require(fromToken_.underlying() != toToken_.underlying(), DuplicateUnderlyingTokens());

        _fromToken = fromToken_;
        _toToken = toToken_;
        _currentBatchId = 1;

        SafeERC20.forceApprove(IERC20(fromToken().underlying()), address(fromToken()), type(uint256).max);
        SafeERC20.forceApprove(IERC20(toToken().underlying()), address(toToken()), type(uint256).max);
    }

    /**
     * @dev Claim the {toToken} and {fromToken} corresponding to `account`'s deposit in batch with id `batchId`.
     *
     * NOTE: This function is not gated and can be called by anyone. Claims could be frontrun.
     */
    function claim(uint256 batchId, address account) public virtual nonReentrant returns (euint64, euint64) {
        return _claim(batchId, account);
    }

    /**
     * @dev Quit the batch with id `batchId`. Entire deposit is returned to the user.
     * This can only be called if the batch has not yet been dispatched or if its route failed.
     *
     * NOTE: Developers should consider adding additional restrictions to {_quit}
     * if maintaining confidentiality of deposits is critical to the application.
     *
     * WARNING: {dispatchBatch} may fail if an incompatible version of {ERC7984ERC20Wrapper} is used.
     * This function must be unrestricted in cases where batch dispatching fails.
     */
    function quit(uint256 batchId) public virtual nonReentrant returns (euint64) {
        return _quit(batchId, msg.sender);
    }

    /**
     * @dev Permissionless function to dispatch the current batch. Increments the {currentBatchId}.
     *
     * NOTE: Developers should consider adding additional restrictions to this function
     * if maintaining confidentiality of deposits is critical to the application.
     */
    function dispatchBatch() public virtual {
        _dispatch(_getAndIncreaseBatchId());
    }

    /**
     * @dev Permissionless function to dispatch again a batch whose route failed.
     *
     * NOTE: Each dispatch publicly decrypts the batch total. Developers should consider adding restrictions, such as a
     * minimum age after the last {quit}, if maintaining confidentiality of deposits is critical to the application.
     */
    function redispatchBatch(uint256 batchId) public virtual {
        _validateStateBitmap(batchId, _encodeStateBitmap(BatchState.Failed));
        _dispatch(batchId);
    }

    /**
     * @dev Dispatch batch callback callable by anyone. This function finalizes the unwrap of {fromToken} and runs
     * {_executeRoute} once. If the route reverts, the input is rewrapped and the batch becomes `Failed`. If it receives
     * its outcome, the batch is finalized. Otherwise the batch becomes `Settling`.
     */
    function dispatchBatchCallback(
        uint256 batchId,
        uint64 unwrapAmountCleartext,
        bytes calldata decryptionProof
    ) public virtual nonReentrant {
        _validateStateBitmap(batchId, _encodeStateBitmap(BatchState.Dispatched));

        bytes32 unwrapRequestId_ = unwrapRequestId(batchId);
        // finalize unwrap call will fail if already called by this contract or by anyone else
        try IERC7984ERC20Wrapper(fromToken()).finalizeUnwrap(unwrapRequestId_, unwrapAmountCleartext, decryptionProof) {
            // No need to validate input since `finalizeUnwrap` request succeeded
        } catch {
            // Must validate input since `finalizeUnwrap` request failed
            bytes32[] memory handles = new bytes32[](1);
            handles[0] = euint64.unwrap(fromToken().unwrapAmount(unwrapRequestId_));
            FHE.checkSignatures(handles, abi.encode(unwrapAmountCleartext), decryptionProof);
        }

        _batches[batchId].unwrapAmount = unwrapAmountCleartext;

        if (unwrapAmountCleartext == 0) {
            _finalize(batchId);
            return;
        }

        uint256 inputAmount = unwrapAmountCleartext * fromToken().rate();
        uint256 fromBalanceBefore = _underlyingBalance(fromToken());
        uint256 toBalanceBefore = _underlyingBalance(toToken());

        // The route runs with an explicit gas budget so that a route running out of gas can be told apart from one
        // that reverts: the former would let any caller fail the batch by underfunding the callback.
        uint256 reserve = _routeFailureGasReserve();
        uint256 routeGas = gasleft() - reserve;
        try this.executeRoute{gas: routeGas}(batchId, unwrapAmountCleartext) returns (bool outcomeReceived) {
            if (outcomeReceived) {
                _finalize(batchId);
            } else {
                require(_underlyingBalance(fromToken()) + inputAmount <= fromBalanceBefore, UnspentInput(batchId));
                require(_underlyingBalance(toToken()) == toBalanceBefore, IntermediateStepBalanceChanged(batchId));
                _batches[batchId].state = BatchState.Settling;
                emit BatchSettling(batchId);
            }
        } catch (bytes memory reason) {
            // A route that ran out of gas used its whole budget, leaving less than `reserve + routeGas / 64`. The
            // callback then reverts so it can be retried with more gas.
            require(gasleft() >= reserve + routeGas / 64, InsufficientRouteGas(batchId));

            // The route's effects are reverted, so the batcher holds the whole unwrapped input.
            fromToken().wrap(address(this), inputAmount);
            _batches[batchId].state = BatchState.Failed;
            _inFlightBatchId = 0;
            emit BatchFailed(batchId, reason);
        }
    }

    /**
     * @dev Permissionless function to progress a `Settling` batch. Runs {_settleRoute} and finalizes the batch once
     * the route reports its outcome received. Can be called repeatedly until then.
     */
    function settleBatch(uint256 batchId) public virtual nonReentrant {
        _validateStateBitmap(batchId, _encodeStateBitmap(BatchState.Settling));

        uint256 fromBalanceBefore = _underlyingBalance(fromToken());
        uint256 toBalanceBefore = _underlyingBalance(toToken());

        if (_settleRoute(batchId, unwrapAmount(batchId))) {
            _finalize(batchId);
        } else {
            require(
                _underlyingBalance(fromToken()) <= fromBalanceBefore &&
                    _underlyingBalance(toToken()) == toBalanceBefore,
                IntermediateStepBalanceChanged(batchId)
            );
        }
    }

    /**
     * @dev Runs {_executeRoute} on behalf of {dispatchBatchCallback}, which calls it externally so that a reverting
     * route can be caught. Only callable by the batcher itself.
     */
    function executeRoute(uint256 batchId, uint256 amount) external returns (bool) {
        require(msg.sender == address(this), Unauthorized());
        return _executeRoute(batchId, amount);
    }

    /**
     * @dev See {IERC7984Receiver-onConfidentialTransferReceived}.
     *
     * Deposit {fromToken} into the current batch.
     *
     * NOTE: See {_claim} to understand how the claimed amounts are calculated. Claim amounts are rounded down. Small
     * deposits may be rounded down to 0 if a rate is less than 1:1.
     */
    function onConfidentialTransferReceived(
        address,
        address from,
        euint64 amount,
        bytes calldata
    ) external returns (ebool) {
        require(msg.sender == address(fromToken()), Unauthorized());
        ebool success = FHE.gt(_join(from, amount), FHE.asEuint64(0));
        FHE.allowTransient(success, msg.sender);
        return success;
    }

    /// @dev Batcher from token. Users deposit this token in exchange for {toToken}.
    function fromToken() public view virtual returns (IERC7984ERC20Wrapper) {
        return _fromToken;
    }

    /// @dev Batcher to token. Users receive this token in exchange for their {fromToken} deposits.
    function toToken() public view virtual returns (IERC7984ERC20Wrapper) {
        return _toToken;
    }

    /// @dev The ongoing batch id. New deposits join this batch.
    function currentBatchId() public view virtual returns (uint256) {
        return _currentBatchId;
    }

    /// @dev The batch that is `Dispatched` or `Settling`, or 0 if there is none.
    function inFlightBatchId() public view virtual returns (uint256) {
        return _inFlightBatchId;
    }

    /// @dev The unwrap request id of the last dispatch of batch with id `batchId`.
    function unwrapRequestId(uint256 batchId) public view virtual returns (bytes32) {
        return _batches[batchId].unwrapRequestId;
    }

    /// @dev The unwrapped amount of {fromToken} for batch with id `batchId`, set by {dispatchBatchCallback}.
    function unwrapAmount(uint256 batchId) public view virtual returns (uint64) {
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

    /// @dev The amount of {toToken} paid per deposited {fromToken} in batch with id `batchId`.
    function exchangeRate(uint256 batchId) public view virtual returns (uint64) {
        return _batches[batchId].exchangeRate;
    }

    /// @dev The amount of {fromToken} returned per deposited {fromToken} in batch with id `batchId`.
    function refundRate(uint256 batchId) public view virtual returns (uint64) {
        return _batches[batchId].refundRate;
    }

    /// @dev The number of decimals of precision for {exchangeRate} and {refundRate}.
    function exchangeRateDecimals() public pure virtual returns (uint8) {
        return 6;
    }

    /// @dev Human readable description of what the batcher does.
    function routeDescription() public pure virtual returns (string memory);

    /// @dev Returns the current state of a batch. Reverts if the batch does not exist.
    function batchState(uint256 batchId) public view virtual returns (BatchState) {
        BatchState state = _batches[batchId].state;
        if (state != BatchState.Pending) {
            return state;
        }
        if (batchId == currentBatchId()) {
            return BatchState.Pending;
        }

        revert BatchNonexistent(batchId);
    }

    /**
     * @dev Claims {toToken} and {fromToken} for `account`'s deposit in batch with id `batchId`. Tokens are always
     * sent to `account`, enabling third-party relayers to claim on behalf of depositors.
     *
     * The {fromToken} part is only sent if the {toToken} part was. A claim that sends nothing leaves the deposit in
     * place so it can be retried; a claim that sends anything clears it.
     *
     * IMPORTANT: This function is not protected against reentrancy. External functions built on top of it
     * must be marked `nonReentrant`, as {claim} is.
     */
    function _claim(uint256 batchId, address account) internal virtual returns (euint64, euint64) {
        _validateStateBitmap(batchId, _encodeStateBitmap(BatchState.Finalized));

        euint64 deposit = deposits(batchId, account);
        require(FHE.isInitialized(deposit), ZeroDeposits(batchId, account));

        (euint64 toTokenSent, euint64 fromTokenSent, euint64 newDeposit) = _payClaim(batchId, account, deposit);

        FHE.allowThis(newDeposit);
        FHE.allow(newDeposit, account);
        _batches[batchId].deposits[account] = newDeposit;

        emit Claimed(batchId, account, toTokenSent, fromTokenSent);

        return (toTokenSent, fromTokenSent);
    }

    /**
     * @dev Quits the batch with id `batchId` for `account`, returning the entire deposit to `account`.
     * This can only be called if the batch has not yet been dispatched or if its route failed.
     *
     * NOTE: Developers should consider adding additional restrictions to this function if maintaining
     * confidentiality of deposits is critical to the application.
     *
     * IMPORTANT: This function is not protected against reentrancy. External functions built on top of it
     * must be marked `nonReentrant`, as {quit} is.
     */
    function _quit(uint256 batchId, address account) internal virtual returns (euint64) {
        _validateStateBitmap(batchId, _encodeStateBitmap(BatchState.Pending) | _encodeStateBitmap(BatchState.Failed));

        euint64 deposit = deposits(batchId, account);
        require(FHE.isInitialized(deposit), ZeroDeposits(batchId, account));

        euint64 totalDeposits_ = totalDeposits(batchId);

        FHE.allowTransient(deposit, address(fromToken()));
        euint64 sent = fromToken().confidentialTransfer(account, deposit);
        euint64 newTotalDeposits = FHE.sub(totalDeposits_, sent);
        euint64 newDeposit = FHE.sub(deposit, sent);

        FHE.allowThis(newTotalDeposits);
        FHE.allowThis(newDeposit);
        FHE.allow(newDeposit, account);

        _batches[batchId].totalDeposits = newTotalDeposits;
        _batches[batchId].deposits[account] = newDeposit;

        emit Quit(batchId, account, sent);

        return sent;
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
        FHE.allowThis(joinedAmount);
        FHE.allow(newDeposits, to);
        FHE.allow(joinedAmount, to);

        _batches[batchId].totalDeposits = newTotalDeposits;
        _batches[batchId].deposits[to] = newDeposits;

        emit Joined(batchId, to, joinedAmount);

        return joinedAmount;
    }

    /**
     * @dev Requests the unwrap of batch `batchId`'s total deposits and marks it in flight. Reverts while another batch
     * is in flight.
     */
    function _dispatch(uint256 batchId) internal virtual {
        uint256 inFlight = inFlightBatchId();
        require(inFlight == 0, BatchInFlight(inFlight));

        euint64 amountToUnwrap = totalDeposits(batchId);
        if (!FHE.isInitialized(amountToUnwrap)) amountToUnwrap = FHE.asEuint64(0);

        FHE.allowTransient(amountToUnwrap, address(fromToken()));
        _batches[batchId].unwrapRequestId = fromToken().unwrap(
            address(this),
            address(this),
            externalEuint64.wrap(euint64.unwrap(amountToUnwrap)),
            ""
        );
        _batches[batchId].state = BatchState.Dispatched;
        _inFlightBatchId = batchId;

        emit BatchDispatched(batchId);
    }

    /**
     * @dev Wraps the whole underlying balance of both tokens and pins the batch's {exchangeRate} and {refundRate}.
     * A batch with no deposits finalizes with both rates at 0.
     */
    function _finalize(uint256 batchId) internal virtual {
        Batch storage batch = _batches[batchId];
        uint64 amount = batch.unwrapAmount;

        // Any dust left after (balance % rate) goes to the next finalized batch.
        uint256 toTokenWrapped = _wrapBalance(toToken());
        uint256 fromTokenWrapped = _wrapBalance(fromToken());

        uint64 exchangeRate_;
        uint64 refundRate_;
        if (amount != 0) {
            exchangeRate_ = SafeCast.toUint64(
                Math.mulDiv(toTokenWrapped, uint256(10) ** exchangeRateDecimals(), amount)
            );
            refundRate_ = SafeCast.toUint64(
                Math.mulDiv(fromTokenWrapped, uint256(10) ** exchangeRateDecimals(), amount)
            );

            // Ensure valid rates: not both 0, and no overflow when calculating user outputs
            require(
                (exchangeRate_ != 0 || refundRate_ != 0) &&
                    toTokenWrapped <= type(uint64).max &&
                    fromTokenWrapped <= type(uint64).max,
                InvalidExchangeRate(batchId, amount, exchangeRate_, refundRate_)
            );
        }

        batch.exchangeRate = exchangeRate_;
        batch.refundRate = refundRate_;
        batch.state = BatchState.Finalized;
        _inFlightBatchId = 0;

        emit BatchFinalized(batchId, exchangeRate_, refundRate_);
    }

    /**
     * @dev Gas {dispatchBatchCallback} keeps back from the route to rewrap the input if the route reverts. A route
     * that reverts after using more than 63/64 of its budget is treated as out of gas and the callback reverts.
     */
    function _routeFailureGasReserve() internal view virtual returns (uint256) {
        return 500_000;
    }

    /**
     * @dev Function which is executed once by {dispatchBatchCallback} after validation and unwrap finalization. The
     * parameter `amount` is the plaintext amount of the `fromToken` which were unwrapped--to attain the underlying
     * tokens received, evaluate `amount * fromToken().rate()`.
     *
     * The function should either:
     *
     * - swap the underlying {fromToken} for underlying {toToken} and return `true`, in which case the batch is
     *   finalized on the batcher's underlying balances;
     * - send the whole underlying {fromToken} input to an external service and return `false`, in which case the
     *   batch becomes `Settling` and {_settleRoute} is called until the outcome is received;
     * - or revert, in which case its effects are reverted, the input is rewrapped and the batch becomes `Failed`.
     *
     * When returning `false`, the function must not leave any of the input in the batcher and must not transfer
     * underlying {toToken} into the batcher.
     *
     * [WARNING]
     * ====
     * When the batch is finalized, the following must hold:
     *
     * - the {exchangeRate} and {refundRate} are not both 0
     * - `toTokenBalance \<= type(uint64).max * toToken().rate()` and `fromTokenBalance \<= type(uint64).max * fromToken().rate()`
     *
     * Where `toTokenBalance` and `fromTokenBalance` are the batcher's balances of underlying {toToken} and
     * {fromToken} when the batch is finalized.
     * ====
     */
    function _executeRoute(uint256 batchId, uint256 amount) internal virtual returns (bool outcomeReceived);

    /**
     * @dev Function which is executed by {settleBatch} while batch `batchId` is `Settling`. Returns `true` once the
     * external service has delivered the outcome, which it may pull into the batcher in this call. Returns `false`
     * otherwise, in which case it must not transfer either underlying token into the batcher.
     *
     * WARNING: This function must eventually return `true`. Failure to do so results in user deposits being locked
     * indefinitely.
     */
    function _settleRoute(uint256 batchId, uint256 amount) internal virtual returns (bool outcomeReceived);

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

    /// @dev Gets the current batch id and increments it.
    function _getAndIncreaseBatchId() internal virtual returns (uint256) {
        return _currentBatchId++;
    }

    /**
     * @dev Encodes a `BatchState` into a `bytes32` representation where each bit enabled corresponds to
     * the underlying position in the `BatchState` enum. For example:
     *
     * 0x000...10000
     *         ^---- Failed
     *          ^--- Finalized
     *           ^-- Settling
     *            ^- Dispatched
     *             ^ Pending
     */
    function _encodeStateBitmap(BatchState batchState_) internal pure returns (bytes32) {
        return bytes32(1 << uint8(batchState_));
    }

    /**
     * @dev Sends `account` its share of both tokens for `deposit` in batch `batchId`, and returns the amounts sent and
     * the deposit left: unchanged if something was owed but nothing was sent, zero otherwise.
     */
    function _payClaim(
        uint256 batchId,
        address account,
        euint64 deposit
    ) private returns (euint64 toTokenSent, euint64 fromTokenSent, euint64 newDeposit) {
        euint64 zero = FHE.asEuint64(0);
        euint64 toTokenAmount = _applyRate(deposit, exchangeRate(batchId));
        euint64 fromTokenAmount = _applyRate(deposit, refundRate(batchId));

        FHE.allowTransient(toTokenAmount, address(toToken()));
        toTokenSent = toToken().confidentialTransfer(account, toTokenAmount);

        ebool toTokenPaid = FHE.or(FHE.eq(toTokenAmount, zero), FHE.ne(toTokenSent, zero));
        euint64 fromTokenToSend = FHE.select(toTokenPaid, fromTokenAmount, zero);
        FHE.allowTransient(fromTokenToSend, address(fromToken()));
        fromTokenSent = fromToken().confidentialTransfer(account, fromTokenToSend);

        ebool sentAnything = FHE.or(FHE.ne(toTokenSent, zero), FHE.ne(fromTokenSent, zero));
        ebool owedAnything = FHE.or(FHE.ne(toTokenAmount, zero), FHE.ne(fromTokenAmount, zero));
        newDeposit = FHE.select(FHE.and(owedAnything, FHE.not(sentAnything)), deposit, zero);
    }

    /// @dev `deposit * rate / 10 ** exchangeRateDecimals()`, rounded down.
    function _applyRate(euint64 deposit, uint64 rate) private returns (euint64) {
        // Overflow is not possible on mul since `type(uint64).max ** 2 < type(uint128).max`.
        // Given that the output of the entire batch must fit in uint64, individual user outputs must also fit.
        return FHE.asEuint64(FHE.div(FHE.mul(FHE.asEuint128(deposit), rate), uint128(10) ** exchangeRateDecimals()));
    }

    /// @dev Wraps the batcher's whole underlying balance of `token` and returns the wrapped amount.
    function _wrapBalance(IERC7984ERC20Wrapper token) private returns (uint256) {
        uint256 balance = _underlyingBalance(token);
        uint256 wrapped = balance / token.rate();
        if (wrapped != 0) token.wrap(address(this), balance);
        return wrapped;
    }

    function _underlyingBalance(IERC7984ERC20Wrapper token) private view returns (uint256) {
        return IERC20(token.underlying()).balanceOf(address(this));
    }
}
