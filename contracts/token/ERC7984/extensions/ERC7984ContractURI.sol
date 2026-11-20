// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (token/ERC7984/extensions/ERC7984ContractURI.sol)

pragma solidity ^0.8.26;

import {ERC7984} from "../ERC7984.sol";

/**
 * @dev Extension of {ERC7984} that adds a {contractURI} function as defined in
 * https://eips.ethereum.org/EIPS/eip-7572[ERC-7572].
 */
abstract contract ERC7984ContractURI is ERC7984 {
    /// @dev Event emitted when the contract URI is changed.
    event ContractURIUpdated();

    string private _contractURI;

    constructor(string memory contractURI_) {
        _setContractURI(contractURI_);
    }

    /// @dev Returns the contract URI.
    function contractURI() public view virtual returns (string memory) {
        return _contractURI;
    }

    /**
     * @dev Sets the {contractURI} for the contract.
     *
     * Emits a {ContractURIUpdated} event.
     */
    function _setContractURI(string memory newContractURI) internal virtual {
        _contractURI = newContractURI;

        emit ContractURIUpdated();
    }
}
