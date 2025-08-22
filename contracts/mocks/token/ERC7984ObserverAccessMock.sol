// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984ObserverAccess} from "../../token/ERC7984/extensions/ERC7984ObserverAccess.sol";
import {ERC7984Mock} from "./ERC7984Mock.sol";

contract ERC7984ObserverAccessMock is ERC7984ObserverAccess, ERC7984Mock {
    constructor(
        string memory name_,
        string memory symbol_,
        string memory tokenURI_
    ) ERC7984Mock(name_, symbol_, tokenURI_) {}

    function _update(
        address from,
        address to,
        euint64 amount
    ) internal virtual override(ERC7984ObserverAccess, ERC7984Mock) returns (euint64) {
        return super._update(from, to, amount);
    }
}
