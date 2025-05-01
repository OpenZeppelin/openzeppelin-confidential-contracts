// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FHE } from "@fhevm/solidity/lib/FHE.sol";
import { FHEVMConfigStruct } from "@fhevm/solidity/lib/Impl.sol";

contract FHEVMTestingConfig {
    constructor() {
        FHE.setCoprocessor(
            FHEVMConfigStruct(
                0xFee8407e2f5e3Ee68ad77cAE98c434e637f516e5,
                0x687408aB54661ba0b4aeF3a44156c616c6955E07,
                0xFb03BE574d14C256D56F09a198B586bdfc0A9de2,
                0x9D6891A6240D6130c54ae243d8005063D05fE14b
            )
        );
        FHE.setDecryptionOracle(0x33347831500F1e73f0ccCBb95c9f86B94d7b1123);
    }
}
