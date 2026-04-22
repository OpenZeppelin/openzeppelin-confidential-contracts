// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {euint64, FHE} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984HolderCapHookModule} from "./../../../../token/ERC7984/utils/ERC7984HolderCapHookModule.sol";

contract ERC7984HolderCapHookModuleMock is ERC7984HolderCapHookModule, ZamaEthereumConfig {
    address private immutable _owner;

    constructor(address owner_) {
        _owner = owner_;
    }

    function _postTransfer(address token, address from, address to, euint64 encryptedAmount) internal override {
        super._postTransfer(token, from, to, encryptedAmount);

        FHE.allow(holderCount(token), _owner);
    }
}
