// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984ContractURI} from "../../token/ERC7984/extensions/ERC7984ContractURI.sol";
import {ERC7984Mock, ERC7984} from "./ERC7984Mock.sol";

contract ERC7984ContractURIMock is ERC7984ContractURI, ERC7984Mock {
    constructor(
        string memory name_,
        string memory symbol_,
        string memory contractURI_
    ) ERC7984Mock(name_, symbol_) ERC7984ContractURI(contractURI_) {}

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC7984ContractURI, ERC7984) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _update(
        address from,
        address to,
        euint64 amount
    ) internal virtual override(ERC7984Mock, ERC7984) returns (euint64) {
        return super._update(from, to, amount);
    }
}
