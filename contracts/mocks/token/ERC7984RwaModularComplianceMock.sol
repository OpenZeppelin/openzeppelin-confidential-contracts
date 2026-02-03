// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984} from "./../../token/ERC7984/ERC7984.sol";
import {ERC7984Rwa} from "./../../token/ERC7984/extensions/ERC7984Rwa.sol";
import {ERC7984RwaModularCompliance} from "./../../token/ERC7984/extensions/rwa/ERC7984RwaModularCompliance.sol";
import {ERC7984Mock} from "./ERC7984Mock.sol";

contract ERC7984RwaModularComplianceMock is ERC7984RwaModularCompliance, ERC7984Mock {
    constructor(
        string memory name,
        string memory symbol,
        string memory tokenUri,
        address admin
    ) ERC7984Rwa(admin) ERC7984Mock(name, symbol, tokenUri) {}

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC7984Rwa, ERC7984) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _update(
        address from,
        address to,
        euint64 amount
    ) internal virtual override(ERC7984Mock, ERC7984RwaModularCompliance) returns (euint64) {
        return super._update(from, to, amount);
    }
}
