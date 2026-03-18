// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC7984} from "./../../token/ERC7984/ERC7984.sol";
import {ERC7984Hooked} from "./../../token/ERC7984/extensions/ERC7984Hooked.sol";
import {ERC7984Mock} from "./ERC7984Mock.sol";

contract ERC7984HookedMock is ERC7984Hooked, ERC7984Mock, Ownable {
    constructor(
        string memory name,
        string memory symbol,
        string memory tokenUri,
        address admin
    ) ERC7984Mock(name, symbol, tokenUri) Ownable(admin) {}

    function _update(
        address from,
        address to,
        euint64 amount
    ) internal virtual override(ERC7984Mock, ERC7984Hooked) returns (euint64) {
        return super._update(from, to, amount);
    }

    function _authorizeModuleChange() internal virtual override onlyOwner {}
}
