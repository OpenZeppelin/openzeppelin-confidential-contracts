// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ComplianceModuleConfidential} from "./../../finance/compliance/ComplianceModuleConfidential.sol";
import {IERC7984} from "./../../interfaces/IERC7984.sol";

contract ComplianceModuleConfidentialMock is ComplianceModuleConfidential, ZamaEthereumConfig {
    bool public isCompliant = true;
    bool public revertOnUninstall = false;

    event PostTransfer();
    event PreTransfer();

    event OnInstall(bytes initData);
    event OnUninstall(bytes deinitData);

    function onInstall(bytes calldata initData) public override {
        emit OnInstall(initData);
        super.onInstall(initData);
    }

    function onUninstall(bytes calldata deinitData) public override {
        if (revertOnUninstall) {
            revert("Revert on uninstall");
        }

        emit OnUninstall(deinitData);
        super.onUninstall(deinitData);
    }

    function setIsCompliant(bool isCompliant_) public {
        isCompliant = isCompliant_;
    }

    function setRevertOnUninstall(bool revertOnUninstall_) public {
        revertOnUninstall = revertOnUninstall_;
    }

    function _isCompliantTransfer(address token, address from, address, euint64) internal override returns (ebool) {
        euint64 fromBalance = IERC7984(token).confidentialBalanceOf(from);

        if (euint64.unwrap(fromBalance) != 0) {
            _getTokenHandleAllowance(token, fromBalance);
            assert(FHE.isAllowed(fromBalance, address(this)));
        }

        emit PreTransfer();
        return FHE.asEbool(isCompliant);
    }

    function _postTransfer(address token, address from, address to, euint64 amount) internal override {
        emit PostTransfer();
        super._postTransfer(token, from, to, amount);
    }
}
