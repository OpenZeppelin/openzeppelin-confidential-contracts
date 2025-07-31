// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {euint128} from "@fhevm/solidity/lib/FHE.sol";
import {VestingWalletConfidential} from "./VestingWalletConfidential.sol";

/**
 * @dev An extension of {VestingWalletConfidential} that adds a cliff to the vesting schedule. The cliff is `cliffSeconds` long and
 * starts at the vesting start timestamp (see {VestingWalletConfidential}).
 */
abstract contract VestingWalletCliffConfidential is VestingWalletConfidential {
    /// @custom:storage-location erc7201:openzeppelin.storage.VestingWalletCliffConfidential
    struct VestingWalletCliffStorage {
        uint64 _cliff;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.VestingWalletCliffConfidential")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line const-name-snakecase
    bytes32 private constant VestingWalletCliffStorageLocation =
        0x3c715f77db997bdb68403fafb54820cd57dedce553ed6315028656b0d601c700;

    /// @dev The specified cliff duration is larger than the vesting duration.
    error VestingWalletCliffConfidentialInvalidCliffDuration(uint64 cliffSeconds, uint64 durationSeconds);

    /// @dev The timestamp at which the cliff ends.
    function cliff() public view virtual returns (uint64) {
        return _getVestingWalletCliffStorage()._cliff;
    }

    /**
     * @dev Set the duration of the cliff, in seconds. The cliff starts at the vesting
     * start timestamp (see {VestingWalletConfidential-start}) and ends `cliffSeconds` later.
     */
    // solhint-disable-next-line func-name-mixedcase
    function __VestingWalletCliffConfidential_init(
        address beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds,
        uint48 cliffSeconds
    ) internal onlyInitializing {
        __VestingWalletConfidential_init(beneficiary, startTimestamp, durationSeconds);
        __VestingWalletCliffConfidential_init_unchained(cliffSeconds);
    }

    // solhint-disable-next-line func-name-mixedcase
    function __VestingWalletCliffConfidential_init_unchained(uint48 cliffSeconds) internal onlyInitializing {
        require(
            cliffSeconds <= duration(),
            VestingWalletCliffConfidentialInvalidCliffDuration(cliffSeconds, duration())
        );

        _getVestingWalletCliffStorage()._cliff = start() + cliffSeconds;
    }

    /**
     * @dev This function returns the amount vested, as a function of time, for
     * an asset given its total historical allocation. Returns 0 if the {cliff} timestamp is not met.
     *
     * IMPORTANT: The cliff not only makes the schedule return 0, but it also ignores every possible side
     * effect from calling the inherited implementation (i.e. `super._vestingSchedule`). Carefully consider
     * this caveat if the overridden implementation of this function has any (e.g. writing to memory or reverting).
     */
    function _vestingSchedule(euint128 totalAllocation, uint64 timestamp) internal virtual override returns (euint128) {
        return timestamp < cliff() ? euint128.wrap(0) : super._vestingSchedule(totalAllocation, timestamp);
    }

    function _getVestingWalletCliffStorage() private pure returns (VestingWalletCliffStorage storage $) {
        assembly {
            $.slot := VestingWalletCliffStorageLocation
        }
    }
}
