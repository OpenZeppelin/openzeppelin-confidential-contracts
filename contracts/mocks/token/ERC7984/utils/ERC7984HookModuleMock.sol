// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984} from "../../../../interfaces/IERC7984.sol";
import {ERC7984HookModule} from "../../../../token/ERC7984/utils/ERC7984HookModule.sol";

contract ERC7984HookModuleMock is ERC7984HookModule, ZamaEthereumConfig {
    bool public isCompliant = true;

    event PostTransfer();
    event PreTransfer();

    event OnInstall(bytes initData);

    function onInstall(bytes calldata initData) public override {
        emit OnInstall(initData);
        super.onInstall(initData);
    }

    function setIsCompliant(bool isCompliant_) public {
        isCompliant = isCompliant_;
    }

    function _preTransfer(address token, address from, address, euint64) internal override returns (ebool) {
        euint64 fromBalance = IERC7984(token).confidentialBalanceOf(from);

        if (FHE.isInitialized(fromBalance)) {
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
