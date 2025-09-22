// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984Rwa} from "../../token/ERC7984/extensions/ERC7984Rwa.sol";
import {FHESafeMath} from "../../utils/FHESafeMath.sol";
import {HandleAccessManager} from "../../utils/HandleAccessManager.sol";

// solhint-disable func-name-mixedcase
contract ERC7984RwaMock is ERC7984Rwa, HandleAccessManager, SepoliaConfig {
    mapping(address account => euint64 encryptedAmount) private _frozenBalances;
    bool public compliantTransfer;

    event PostTransfer(address from, address to, euint64 encryptedAmount);
    event PostForceTransfer(address from, address to, euint64 encryptedAmount);

    constructor(string memory name, string memory symbol, string memory tokenUri) ERC7984Rwa(name, symbol, tokenUri) {}

    function createEncryptedAmount(uint64 amount) public returns (euint64 encryptedAmount) {
        FHE.allowThis(encryptedAmount = FHE.asEuint64(amount));
        FHE.allow(encryptedAmount, msg.sender);
    }

    function $_setCompliantTransfer() public {
        compliantTransfer = true;
    }

    function $_unsetCompliantTransfer() public {
        compliantTransfer = false;
    }

    function $_mint(address to, uint64 amount) public returns (euint64 transferred) {
        return _mint(to, FHE.asEuint64(amount));
    }

    function _preCheckTransfer(
        address /*from*/,
        address /*to*/,
        euint64 /*encryptedAmount*/
    ) internal override returns (ebool) {
        return FHE.asEbool(compliantTransfer);
    }

    function _preCheckForceTransfer(
        address /*from*/,
        address /*to*/,
        euint64 /*encryptedAmount*/
    ) internal override returns (ebool) {
        return FHE.asEbool(compliantTransfer);
    }

    function _postTransfer(address from, address to, euint64 encryptedAmount) internal override {
        emit PostTransfer(from, to, encryptedAmount);
    }

    function _postForceTransfer(address from, address to, euint64 encryptedAmount) internal override {
        emit PostForceTransfer(from, to, encryptedAmount);
    }

    function _validateHandleAllowance(bytes32 handle) internal view override onlyAgent {}
}
