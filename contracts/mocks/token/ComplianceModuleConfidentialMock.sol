// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984RwaComplianceModule} from "../../token/ERC7984/extensions/rwa/ERC7984RwaComplianceModule.sol";

contract ComplianceModuleConfidentialMock is ERC7984RwaComplianceModule, ZamaEthereumConfig {
    bool public isCompliant = false;

    event PostTransfer();
    event PreTransfer();

    function setIsCompliant(bool isCompliant_) public {
        isCompliant = isCompliant_;
    }

    function _isCompliantTransfer(address, address, address, euint64) internal override returns (ebool) {
        emit PreTransfer();
        return FHE.asEbool(isCompliant);
    }

    function _postTransfer(address, address, address, euint64) internal override {
        emit PostTransfer();
    }
}
