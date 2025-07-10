// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VestingWalletExecutorConfidential} from "./VestingWalletExecutorConfidential.sol";

contract VestingWalletExecutorConfidentialImpl is VestingWalletExecutorConfidential {
    function initialize(
        address executor,
        address beneficiary,
        uint48 startTimestamp,
        uint48 durationSeconds
    ) public virtual initializer {
        __VestingWalletConfidential_init(beneficiary, startTimestamp, durationSeconds);
        __VestingWalletExecutorConfidential_init(executor);
    }
}
