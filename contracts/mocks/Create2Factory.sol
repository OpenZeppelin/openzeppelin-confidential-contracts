// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract Create2Factory {
    event Deployed(address clone);

    function create2(address impl, bytes memory data) public returns (address) {
        address deployedTo = Clones.clone(impl);
        (bool success, ) = deployedTo.call(data);
        if (!success) {
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }

        emit Deployed(deployedTo);
        return deployedTo;
    }
}
