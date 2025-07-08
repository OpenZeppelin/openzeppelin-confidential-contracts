// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";

import {IConfidentialFungibleToken} from "../interfaces/IConfidentialFungibleToken.sol";
import {TFHESafeMath} from "../utils/TFHESafeMath.sol";

/**
 * @dev A vesting wallet is an ownable contract that can receive ConfidentialFungibleTokens, and release these
 * assets to the wallet owner, also referred to as "beneficiary", according to a vesting schedule.
 *
 * Any assets transferred to this contract will follow the vesting schedule as if they were locked from the beginning.
 * Consequently, if the vesting has already started, any amount of tokens sent to this contract will (at least partly)
 * be immediately releasable.
 *
 * By setting the duration to 0, one can configure this contract to behave like an asset timelock that holds tokens for
 * a beneficiary until a specified time.
 *
 * NOTE: Since the wallet is {Ownable}, and ownership can be transferred, it is possible to sell unvested tokens.
 *
 * NOTE: When using this contract with any token whose balance is adjusted automatically (i.e. a rebase token), make
 * sure to account the supply/balance adjustment in the vesting schedule to ensure the vested amount is as intended.
 */
contract VestingWalletConfidential is OwnableUpgradeable {
    mapping(address token => euint64) private _tokenReleased;
    uint64 private _start;
    uint64 private _duration;
    address private _executor;

    event VestingWalletConfidentialTokenReleased(address indexed token, euint64 amount);
    event VestingWalletCallExecuted(address indexed target, uint256 value, bytes data);

    error VestingWalletConfidentialInvalidDuration();
    error VestingWalletConfidentialOnlyExecutor();

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address executor_,
        address beneficiary,
        uint64 startTimestamp,
        uint64 durationSeconds
    ) public virtual initializer {
        __Ownable_init(beneficiary);
        _start = startTimestamp;
        _duration = durationSeconds;
        _executor = executor_;
    }

    function executor() public view virtual returns (address) {
        return _executor;
    }

    /**
     * @dev Getter for the start timestamp.
     */
    function start() public view virtual returns (uint64) {
        return _start;
    }

    /**
     * @dev Getter for the vesting duration.
     */
    function duration() public view virtual returns (uint64) {
        return _duration;
    }

    /**
     * @dev Getter for the end timestamp.
     */
    function end() public view virtual returns (uint64) {
        return start() + duration();
    }

    /**
     * @dev Amount of token already released
     */
    function released(address token) public view virtual returns (euint64) {
        return _tokenReleased[token];
    }

    /**
     * @dev Getter for the amount of releasable `token` tokens. `token` should be the address of an
     * {IConfidentialFungibleToken} contract.
     */
    function releasable(address token) public virtual returns (euint64) {
        // vestedAmount >= released so this cannot overflow. released & vestedAmount can be 0 but are handled gracefully.
        return FHE.sub(vestedAmount(token, uint64(block.timestamp)), released(token));
    }

    /**
     * @dev Release the tokens that have already vested.
     *
     * Emits a {ConfidentialFungibleTokenReleased} event.
     */
    function release(address token) public virtual {
        euint64 amount = releasable(token);
        FHE.allowTransient(amount, token);
        euint64 amountSent = IConfidentialFungibleToken(token).confidentialTransfer(owner(), amount);

        // TODO: Could theoretically overflow
        euint64 newReleasedAmount = FHE.add(released(token), amountSent);
        FHE.allow(newReleasedAmount, owner());
        FHE.allowThis(newReleasedAmount);
        _tokenReleased[token] = newReleasedAmount;
        emit VestingWalletConfidentialTokenReleased(token, amountSent);
    }

    /**
     * @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
     */
    function vestedAmount(address token, uint64 timestamp) public virtual returns (euint64) {
        return
            _vestingSchedule(
                // TODO: Could theoretically overflow
                FHE.add(IConfidentialFungibleToken(token).balanceOf(address(this)), released(token)),
                timestamp
            );
    }

    function call(address target, uint256 value, bytes memory data) public virtual {
        require(msg.sender == executor(), VestingWalletConfidentialOnlyExecutor());
        _call(target, value, data);
    }

    function _call(address target, uint256 value, bytes memory data) internal virtual {
        (bool success, bytes memory res) = target.call{value: value}(data);
        Address.verifyCallResult(success, res);

        emit VestingWalletCallExecuted(target, value, data);
    }

    /**
     * @dev Virtual implementation of the vesting formula. This returns the amount vested, as a function of time, for
     * an asset given its total historical allocation.
     */
    function _vestingSchedule(euint64 totalAllocation, uint64 timestamp) internal virtual returns (euint64) {
        if (timestamp < start()) {
            return euint64.wrap(0);
        } else if (timestamp >= end()) {
            return totalAllocation;
        } else {
            return FHE.div(FHE.mul(totalAllocation, (timestamp - start())), duration());
        }
    }
}
