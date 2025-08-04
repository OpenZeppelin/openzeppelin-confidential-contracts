// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {ACLAllowance} from "../../utils/ACLAllowance.sol";

contract ACLAllowanceMock is ACLAllowance, SepoliaConfig {
    event HandleCreated(euint64 handle);

    function _validateACLAllowance(bytes32 handle) internal view override {}

    function createHandle(uint64 amount) public returns (euint64) {
        euint64 handle = FHE.asEuint64(amount);
        FHE.allow(handle, address(this));

        emit HandleCreated(handle);
        return handle;
    }
}
