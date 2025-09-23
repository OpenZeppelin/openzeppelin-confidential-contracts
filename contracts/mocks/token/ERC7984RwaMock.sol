// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984Rwa} from "../../token/ERC7984/extensions/ERC7984Rwa.sol";
import {HandleAccessManager} from "../../utils/HandleAccessManager.sol";

// solhint-disable func-name-mixedcase
contract ERC7984RwaMock is ERC7984Rwa, HandleAccessManager, SepoliaConfig {
    constructor(
        string memory name,
        string memory symbol,
        string memory tokenUri,
        address admin
    ) ERC7984Rwa(name, symbol, tokenUri, admin) {}

    function createEncryptedAmount(uint64 amount) public returns (euint64 encryptedAmount) {
        FHE.allowThis(encryptedAmount = FHE.asEuint64(amount));
        FHE.allow(encryptedAmount, msg.sender);
    }

    function $_mint(address to, uint64 amount) public returns (euint64 transferred) {
        return _mint(to, FHE.asEuint64(amount));
    }

    function _validateHandleAllowance(bytes32 handle) internal view override onlyAgent {}
}
