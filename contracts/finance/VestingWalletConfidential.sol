// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.2.0) (finance/VestingWalletConfidential.sol)
pragma solidity ^0.8.24;

import {FHE, ebool, euint64, euint128} from "@fhevm/solidity/lib/FHE.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC7984} from "./../interfaces/IERC7984.sol";

/**
 * @dev A vesting wallet is an ownable contract that can receive ERC7984 tokens, and release these
 * assets to the wallet owner, also referred to as "beneficiary", according to a vesting schedule.
 *
 * Any assets transferred to this contract will follow the vesting schedule as if they were locked from the beginning.
 * Consequently, if the vesting has already started, any amount of tokens sent to this contract will (at least partly)
 * be immediately releasable.
 *
 * By setting the duration to 0, one can configure this contract to behave like an asset timelock that holds tokens for
 * a beneficiary until a specified time.
 *
 * NOTE: Since the wallet is `Ownable`, and ownership can be transferred, it is possible to sell unvested tokens.
 *
 * NOTE: When using this contract with any token whose balance is adjusted automatically (i.e. a rebase token), make
 * sure to account the supply/balance adjustment in the vesting schedule to ensure the vested amount is as intended.
 *
 * Confidential vesting wallet contracts can be deployed (as clones) using the {VestingWalletConfidentialFactory}.
 */
abstract contract VestingWalletConfidential is OwnableUpgradeable, ReentrancyGuardTransient {
    /// @custom:storage-location erc7201:openzeppelin.storage.VestingWalletConfidential
    struct VestingWalletStorage {
        mapping(address token => euint128) _tokenReleased;
        uint64 _start;
        uint64 _duration;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.VestingWalletConfidential")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line const-name-snakecase
    bytes32 private constant VestingWalletStorageLocation =
        0x78ce9ee9eb65fa0cf5bf10e861c3a95cb7c3c713c96ab1e5323a21e846796800;

    /// @dev Emitted when releasable vested tokens are released.
    event VestingWalletConfidentialTokenReleased(address indexed token, euint64 amount);

    /// @dev Timestamp at which the vesting starts.
    function start() public view virtual returns (uint64) {
        return _getVestingWalletStorage()._start;
    }

    /// @dev Duration of the vesting in seconds.
    function duration() public view virtual returns (uint64) {
        return _getVestingWalletStorage()._duration;
    }

    /// @dev Timestamp at which the vesting ends.
    function end() public view virtual returns (uint64) {
        return start() + duration();
    }

    /// @dev Amount of token already released
    function released(address token) public view virtual returns (euint128) {
        return _getVestingWalletStorage()._tokenReleased[token];
    }

    /**
     * @dev Getter for the amount of releasable `token` tokens. `token` should be the address of an
     * {IERC7984} contract.
     */
    function releasable(address token) public virtual returns (euint64) {
        euint128 vestedAmount_ = vestedAmount(token, uint48(block.timestamp));
        euint128 releasedAmount = released(token);
        ebool success = FHE.ge(vestedAmount_, releasedAmount);
        return FHE.select(success, FHE.asEuint64(FHE.sub(vestedAmount_, releasedAmount)), FHE.asEuint64(0));
    }

    /**
     * @dev Release the tokens that have already vested.
     *
     * Emits a {VestingWalletConfidentialTokenReleased} event.
     */
    function release(address token) public virtual nonReentrant {
        euint64 amount = releasable(token);
        FHE.allowTransient(amount, token);
        euint64 amountSent = IERC7984(token).confidentialTransfer(owner(), amount);

        // This could overflow if the total supply is resent `type(uint128).max/type(uint64).max` times. This is an accepted risk.
        euint128 newReleasedAmount = FHE.add(released(token), amountSent);
        FHE.allow(newReleasedAmount, owner());
        FHE.allowThis(newReleasedAmount);
        _getVestingWalletStorage()._tokenReleased[token] = newReleasedAmount;
        emit VestingWalletConfidentialTokenReleased(token, amountSent);
    }

    /**
     * @dev Calculates the amount of tokens that have been vested at the given timestamp.
     * Default implementation is a linear vesting curve.
     */
    function vestedAmount(address token, uint48 timestamp) public virtual returns (euint128) {
        return
            _vestingSchedule(FHE.add(released(token), IERC7984(token).confidentialBalanceOf(address(this))), timestamp);
    }

    /**
     * @dev Initializes the vesting wallet for a given `beneficiary` with a start time of `startTimestamp`
     * and an end time of `startTimestamp + durationSeconds`.
     */
    // solhint-disable-next-line func-name-mixedcase
    function __VestingWalletConfidential_init(
        address beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds
    ) internal onlyInitializing {
        __Ownable_init(beneficiary);
        __VestingWalletConfidential_init_unchained(startTimestamp, durationSeconds);
    }

    // solhint-disable-next-line func-name-mixedcase
    function __VestingWalletConfidential_init_unchained(
        uint48 startTimestamp,
        uint48 durationSeconds
    ) internal onlyInitializing {
        VestingWalletStorage storage $ = _getVestingWalletStorage();
        $._start = startTimestamp;
        $._duration = durationSeconds;
    }

    /// @dev This returns the amount vested, as a function of time, for an asset given its total historical allocation.
    function _vestingSchedule(euint128 totalAllocation, uint48 timestamp) internal virtual returns (euint128) {
        if (timestamp < start()) {
            return euint128.wrap(0);
        } else if (timestamp >= end()) {
            return totalAllocation;
        } else {
            return FHE.div(FHE.mul(totalAllocation, (timestamp - start())), duration());
        }
    }

    function _getVestingWalletStorage() private pure returns (VestingWalletStorage storage $) {
        assembly ("memory-safe") {
            $.slot := VestingWalletStorageLocation
        }
    }
}
