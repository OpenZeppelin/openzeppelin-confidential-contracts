// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {Impl} from "@fhevm/solidity/lib/Impl.sol";
import {ERC7984Rwa} from "../../token/ERC7984/extensions/ERC7984Rwa.sol";
import {FHESafeMath} from "../../utils/FHESafeMath.sol";
import {HandleAccessManager} from "../../utils/HandleAccessManager.sol";

// solhint-disable func-name-mixedcase
contract ERC7984RwaMock is ERC7984Rwa, HandleAccessManager, SepoliaConfig {
    mapping(address account => euint64 encryptedAmount) private _frozenBalances;
    bool public compliantTransfer = false;
    bool public compliantForceTransfer = false;

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

    function $_setCompliantForceTransfer() public {
        compliantForceTransfer = true;
    }

    function $_unsetCompliantForceTransfer() public {
        compliantForceTransfer = false;
    }

    function $_mint(address to, uint64 amount) public returns (euint64 transferred) {
        return _mint(to, FHE.asEuint64(amount));
    }

    function _preCheckTransfer(
        address /*from*/,
        address /*to*/,
        euint64 /*encryptedAmount*/
    ) internal override returns (ebool compliant) {
        compliant = FHE.asEbool(compliantTransfer);
        FHE.allowThis(compliant);
    }

    function _preCheckForceTransfer(
        address /*from*/,
        address /*to*/,
        euint64 /*encryptedAmount*/
    ) internal override returns (ebool compliant) {
        compliant = FHE.asEbool(compliantForceTransfer);
        FHE.allowThis(compliant);
    }

    function _validateHandleAllowance(bytes32 handle) internal view override onlyAgent {}
}
