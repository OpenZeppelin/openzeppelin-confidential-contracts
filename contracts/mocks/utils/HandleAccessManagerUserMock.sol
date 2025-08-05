// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {Impl} from "@fhevm/solidity/lib/FHE.sol";
import {HandleAccessManager} from "./../../utils/HandleAccessManager.sol";

contract HandleAccessManagerUserMock is SepoliaConfig {
    function getTransientAllowance(HandleAccessManager allowance, bytes32 handle) public {
        allowance.getHandleAllowance(handle, address(this), false);
        require(Impl.isAllowed(handle, address(this)), "HandleAccessManagerUserMock: Not allowed");
    }
}
