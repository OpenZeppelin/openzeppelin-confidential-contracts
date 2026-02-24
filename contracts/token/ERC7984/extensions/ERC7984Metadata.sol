// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (token/ERC7984/extensions/ERC7984Metadata.sol)
pragma solidity ^0.8.27;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC7984Metadata} from "../../../interfaces/IERC7984Metadata.sol";
import {ERC7984} from "../ERC7984.sol";

/**
 * @dev Extension of {ERC7984} that adds a {contractURI} function.
 */
abstract contract ERC7984Metadata is IERC7984Metadata, ERC7984 {
    string private _contractURI;

    constructor(string memory contractURI_) {
        _contractURI = contractURI_;
    }

    /// @inheritdoc IERC7984Metadata
    function contractURI() public view virtual returns (string memory) {
        return _contractURI;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC7984, IERC165) returns (bool) {
        return interfaceId == type(IERC7984Metadata).interfaceId || super.supportsInterface(interfaceId);
    }
}
