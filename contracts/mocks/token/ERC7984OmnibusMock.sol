// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984Omnibus} from "../../token/ERC7984/extensions/ERC7984Omnibus.sol";
import {ERC7984Mock, ERC7984} from "./ERC7984Mock.sol";

abstract contract ERC7984OmnibusMock is ERC7984Omnibus, ERC7984Mock {
    function _update(
        address from,
        address to,
        euint64 amount
    ) internal virtual override(ERC7984Mock, ERC7984) returns (euint64) {
        return super._update(from, to, amount);
    }
}
