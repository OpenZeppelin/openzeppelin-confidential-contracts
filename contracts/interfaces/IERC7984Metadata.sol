// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (token/ERC7984/IERC7984Metadata.sol)
pragma solidity ^0.8.24;

import {IERC7984} from "./IERC7984.sol";

/// @dev Interface for optional metadata functions for {IERC7984}.
interface IERC7984Metadata is IERC7984 {
    /// @dev Returns the contract URI. Should be formatted as described in https://eips.ethereum.org/EIPS/eip-7572[ERC-7572].
    function contractURI() external view returns (string memory);
}
