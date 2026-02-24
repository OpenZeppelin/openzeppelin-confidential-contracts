// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ComplianceModuleConfidential} from "./ComplianceModuleConfidential.sol";

interface IIdentityRegistry {
    function isVerified(address user) external view returns (bool);
}

interface IToken {
    function identityRegistry() external view returns (IIdentityRegistry);
}

contract IdentityComplianceModuleConfidential is ComplianceModuleConfidential {
    error AddressNotVerified(address user);

    /// @inheritdoc ComplianceModuleConfidential
    function _isCompliantTransfer(
        address token,
        address,
        address to,
        euint64
    ) internal virtual override returns (ebool) {
        require(IToken(token).identityRegistry().isVerified(to), AddressNotVerified(to));

        return FHE.allow(FHE.asEbool(true), msg.sender);
    }
}
