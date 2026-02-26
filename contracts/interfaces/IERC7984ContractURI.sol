// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IERC7984} from "./IERC7984.sol";

/// @dev Interface for the optional {contractURI} function for {IERC7984}.
interface IERC7984ContractURI is IERC7984 {
    /// @dev Returns the contract URI. Should be formatted as described in https://eips.ethereum.org/EIPS/eip-7572[ERC-7572].
    function contractURI() external view returns (string memory);
}
