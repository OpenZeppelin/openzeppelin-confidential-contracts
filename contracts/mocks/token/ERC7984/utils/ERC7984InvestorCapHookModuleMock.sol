// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {euint64, FHE} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984InvestorCapHookModule} from "./../../../../token/ERC7984/utils/ERC7984InvestorCapHookModule.sol";

contract ERC7984InvestorCapHookModuleMock is ERC7984InvestorCapHookModule, ZamaEthereumConfig {
    address private immutable _owner;

    constructor(address owner_) {
        _owner = owner_;
    }

    function _postTransfer(address token, address from, address to, euint64 encryptedAmount) internal override {
        super._postTransfer(token, from, to, encryptedAmount);

        FHE.allow(investorCount(token), _owner);
    }
}
