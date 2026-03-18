// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984} from "../../token/ERC7984/ERC7984.sol";
import {ERC7984IdentityCheck} from "../../token/ERC7984/extensions/ERC7984IdentityCheck.sol";
import {HandleAccessManager} from "../../utils/HandleAccessManager.sol";
import {ERC7984Mock} from "./ERC7984Mock.sol";

contract ERC7984IdentityCheckMock is ERC7984Mock, ERC7984IdentityCheck {
    constructor(
        address identityRegistry,
        string memory name,
        string memory symbol,
        string memory tokenUri
    ) ERC7984Mock(name, symbol, tokenUri) ERC7984IdentityCheck(identityRegistry) {}

    function _update(
        address from,
        address to,
        euint64 amount
    ) internal virtual override(ERC7984Mock, ERC7984IdentityCheck) returns (euint64) {
        return super._update(from, to, amount);
    }
}
