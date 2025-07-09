// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IConfidentialFungibleToken} from "./../interfaces/IConfidentialFungibleToken.sol";
import {TFHESafeMath} from "./../utils/TFHESafeMath.sol";

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
abstract contract VestingWalletConfidential is OwnableUpgradeable, ReentrancyGuardTransient {
    event VestingWalletConfidentialTokenReleased(address indexed token, euint64 amount);

    error VestingWalletConfidentialInvalidDuration();

    /// @custom:storage-location erc7201:openzeppelin.storage.VestingWalletConfidential
    struct VestingWalletStorage {
        mapping(address token => euint64) _tokenReleased;
        uint64 _start;
        uint64 _duration;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.VestingWalletConfidential")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VestingWalletStorageLocation =
        0x78ce9ee9eb65fa0cf5bf10e861c3a95cb7c3c713c96ab1e5323a21e846796800;

    function _getVestingWalletStorage() private pure returns (VestingWalletStorage storage $) {
        assembly {
            $.slot := VestingWalletStorageLocation
        }
    }

    // solhint-disable-next-line func-name-mixedcase
    function __VestingWalletConfidential_init(
        address beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds
    ) internal onlyInitializing {
        __Ownable_init(beneficiary);
        VestingWalletStorage storage $ = _getVestingWalletStorage();
        $._start = startTimestamp;
        $._duration = durationSeconds;
    }

    /// @dev Timestamp at which the vesting starts.
    function start() public view virtual returns (uint64) {
        VestingWalletStorage storage $ = _getVestingWalletStorage();
        return $._start;
    }

    /// @dev Duration of the vesting in seconds.
    function duration() public view virtual returns (uint64) {
        VestingWalletStorage storage $ = _getVestingWalletStorage();
        return $._duration;
    }

    /// @dev Timestamp at which the vesting ends.
    function end() public view virtual returns (uint64) {
        return start() + duration();
    }

    /// @dev Amount of token already released
    function released(address token) public view virtual returns (euint64) {
        VestingWalletStorage storage $ = _getVestingWalletStorage();
        return $._tokenReleased[token];
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
    function release(address token) public virtual nonReentrant {
        VestingWalletStorage storage $ = _getVestingWalletStorage();
        euint64 amount = releasable(token);
        FHE.allowTransient(amount, token);
        euint64 amountSent = IConfidentialFungibleToken(token).confidentialTransfer(owner(), amount);

        // TODO: Could theoretically overflow
        euint64 newReleasedAmount = FHE.add(released(token), amountSent);
        FHE.allow(newReleasedAmount, owner());
        FHE.allowThis(newReleasedAmount);
        $._tokenReleased[token] = newReleasedAmount;
        emit VestingWalletConfidentialTokenReleased(token, amountSent);
    }

    /// @dev Calculates the amount of tokens that has already vested. Default implementation is a linear vesting curve.
    function vestedAmount(address token, uint64 timestamp) public virtual returns (euint64) {
        return
            _vestingSchedule(
                // TODO: Could theoretically overflow
                FHE.add(IConfidentialFungibleToken(token).confidentialBalanceOf(address(this)), released(token)),
                timestamp
            );
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
