// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984RwaComplianceModule} from "../../token/ERC7984/extensions/rwa/ERC7984RwaComplianceModule.sol";

// solhint-disable func-name-mixedcase
contract ERC7984RwaModularComplianceModuleMock is ERC7984RwaComplianceModule, ZamaEthereumConfig {
    bool private _compliant = false;

    event PostTransfer();
    event PreTransfer();

    function $_setCompliant() public {
        _compliant = true;
    }

    function $_unsetCompliant() public {
        _compliant = false;
    }

    function _isCompliantTransfer(
        address /*token*/,
        address /*from*/,
        address /*to*/,
        euint64 /*encryptedAmount*/
    ) internal override returns (ebool) {
        emit PreTransfer();
        return FHE.asEbool(_compliant);
    }

    function _postTransfer(
        address /*token*/,
        address /*from*/,
        address /*to*/,
        euint64 /*encryptedAmount*/
    ) internal override {
        emit PostTransfer();
    }
}
