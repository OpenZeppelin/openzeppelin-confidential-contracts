// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VestingWalletConfidential} from "./VestingWalletConfidential.sol";
import {VestingWalletCliffConfidential} from "./VestingWalletCliffConfidential.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VestingWalletCliffConfidentialInitializable is Initializable, VestingWalletCliffConfidential {
    address private _executor;
    uint64 private _start;
    uint64 private _duration;
    uint64 private _cliff;

    constructor() VestingWalletCliffConfidential(0) VestingWalletConfidential(address(0), address(1), 0, 0) {}

    function initialize(
        address executor_,
        address beneficiary,
        uint64 startTimestamp,
        uint64 durationSeconds,
        uint64 cliffSeconds
    ) public virtual initializer {
        require(beneficiary != address(0), Ownable.OwnableInvalidOwner(address(0)));
        _transferOwnership(beneficiary);

        _executor = executor_;
        _start = startTimestamp;
        _duration = durationSeconds;

        if (cliffSeconds > duration()) {
            revert InvalidCliffDuration(cliffSeconds, duration());
        }
        _cliff = start() + cliffSeconds;
    }

    /// @inheritdoc VestingWalletConfidential
    function executor() public view virtual override returns (address) {
        return _executor;
    }

    /// @inheritdoc VestingWalletConfidential
    function start() public view virtual override returns (uint64) {
        return _start;
    }

    /// @inheritdoc VestingWalletConfidential
    function duration() public view virtual override returns (uint64) {
        return _duration;
    }

    /// @inheritdoc VestingWalletCliffConfidential
    function cliff() public view virtual override returns (uint64) {
        return _cliff;
    }
}
