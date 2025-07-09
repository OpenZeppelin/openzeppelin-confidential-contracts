// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VestingWalletConfidential} from "./VestingWalletConfidential.sol";

contract VestingWalletConfidentialUpgradeable is VestingWalletConfidential {
    function initialize(
        address executor_,
        address beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds
    ) public virtual initializer {
        require(beneficiary != address(0), Ownable.OwnableInvalidOwner(address(0)));
        __VestingWalletConfidential_init(executor_, startTimestamp, durationSeconds);
    }
}
