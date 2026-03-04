// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (token/ERC7984/extensions/ERC7984ContractURI.sol)
pragma solidity ^0.8.27;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC7984ContractURI} from "../../../interfaces/IERC7984ContractURI.sol";
import {ERC7984} from "../ERC7984.sol";

/**
 * @dev Extension of {ERC7984} that adds a {contractURI} function.
 */
abstract contract ERC7984ContractURI is IERC7984ContractURI, ERC7984 {
    /// @dev Event emitted when the contract URI is changed.
    event ContractURIUpdated();

    string private _contractURI;

    constructor(string memory contractURI_) {
        _setContractURI(contractURI_);
    }

    /// @inheritdoc IERC7984ContractURI
    function contractURI() public view virtual returns (string memory) {
        return _contractURI;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC7984, IERC165) returns (bool) {
        return interfaceId == type(IERC7984ContractURI).interfaceId || super.supportsInterface(interfaceId);
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
