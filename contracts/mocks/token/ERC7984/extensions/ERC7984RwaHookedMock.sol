// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC7984Hooked} from "../../../../token/ERC7984/extensions/ERC7984Hooked.sol";
import {ERC7984RwaMock} from "../../ERC7984RwaMock.sol";
import {euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984} from "../../../../token/ERC7984/ERC7984.sol";

abstract contract ERC7984RwaHookedMock is ERC7984RwaMock, ERC7984Hooked {
    constructor(
        string memory name,
        string memory symbol,
        string memory tokenUri,
        address admin
    ) ERC7984RwaMock(name, symbol, tokenUri, admin) {}

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC7984RwaMock, ERC7984) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _update(
        address from,
        address to,
        euint64 amount
    ) internal virtual override(ERC7984RwaMock, ERC7984Hooked) returns (euint64) {
        return super._update(from, to, amount);
    }

    function _validateHandleAllowance(
        bytes32 handle
    ) internal view override(ERC7984Hooked, ERC7984RwaMock) returns (bool) {
        return super._validateHandleAllowance(handle);
    }

    function _authorizeModuleChange() internal virtual override onlyAdmin {}
}
