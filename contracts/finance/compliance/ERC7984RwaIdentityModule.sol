// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC7984} from "../../../../interfaces/IERC7984.sol";
import {FHESafeMath} from "../../../../utils/FHESafeMath.sol";
import {ERC7984RwaComplianceModule} from "./ERC7984RwaComplianceModule.sol";

interface IIdentityRegistry {
    function isVerified(address user) external view returns (bool);
}

interface IToken {
    function identityRegistry() external view returns (IIdentityRegistry);
}

contract ERC7984IdentityComplianceModule is ERC7984RwaComplianceModule {
    error AddressNotVerified(address user);

    function _isCompliantTransfer(
        address token,
        address,
        address to,
        euint64
    ) internal virtual override returns (ebool) {
        require(IToken(token).identityRegistry().isVerified(to), AddressNotVerified(to));
    }
}
