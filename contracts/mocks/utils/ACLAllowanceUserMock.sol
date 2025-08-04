// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {Impl} from "@fhevm/solidity/lib/FHE.sol";
import {ACLAllowance} from "./../../utils/ACLAllowance.sol";

contract ACLAllowanceUserMock is SepoliaConfig {
    function getTransientAllowance(ACLAllowance allowance, bytes32 handle) public {
        allowance.getACLAllowance(handle, address(this), false);
        require(Impl.isAllowed(handle, address(this)), "ACLAllowanceUserMock: Not allowed");
    }
}
