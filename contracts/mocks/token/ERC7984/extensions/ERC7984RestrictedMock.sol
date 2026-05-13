// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984Restricted} from "../../../../token/ERC7984/extensions/ERC7984Restricted.sol";
import {ERC7984Mock} from "../ERC7984Mock.sol";

abstract contract ERC7984RestrictedMock is ERC7984Restricted, ERC7984Mock {
    function _update(
        address from,
        address to,
        euint64 amount,
        bool isForced
    ) internal virtual override(ERC7984Mock, ERC7984Restricted) returns (euint64) {
        return super._update(from, to, amount, isForced);
    }
}
