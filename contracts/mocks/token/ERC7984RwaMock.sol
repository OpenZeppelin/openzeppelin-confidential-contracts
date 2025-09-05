// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64, externalEuint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {Impl} from "@fhevm/solidity/lib/Impl.sol";
import {ERC7984Rwa} from "../../token/ERC7984/extensions/ERC7984Rwa.sol";
import {FHESafeMath} from "../../utils/FHESafeMath.sol";
import {HandleAccessManager} from "../../utils/HandleAccessManager.sol";

// solhint-disable func-name-mixedcase
contract ERC7984RwaMock is ERC7984Rwa, HandleAccessManager, SepoliaConfig {
    mapping(address account => euint64 encryptedAmount) private _frozenBalances;
    bool public compliantTransfer;
    bool public compliantForceTransfer;

    // TODO: Move modifiers to `ERC7984Rwa` or remove from mock if useless
    /// @dev Checks if the sender is an admin.
    modifier onlyAdmin() {
        require(isAdmin(_msgSender()), UnauthorizedSender(_msgSender()));
        _;
    }
    /// @dev Checks if the sender is an agent.
    modifier onlyAgent() {
        require(isAgent(_msgSender()), UnauthorizedSender(_msgSender()));
        _;
    }

    constructor(string memory name, string memory symbol, string memory tokenUri) ERC7984Rwa(name, symbol, tokenUri) {}

    function createEncryptedAmount(uint64 amount) public returns (euint64 encryptedAmount) {
        FHE.allowThis(encryptedAmount = FHE.asEuint64(amount));
        FHE.allow(encryptedAmount, msg.sender);
    }

    function $_setCompliant() public {
        compliantTransfer = true;
    }

    function $_unsetCompliant() public {
        compliantTransfer = false;
    }

    function $_setForceCompliant() public {
        compliantForceTransfer = true;
    }

    function $_unsetForceCompliant() public {
        compliantForceTransfer = false;
    }

    function $_mint(address to, uint64 amount) public returns (euint64 transferred) {
        return _mint(to, FHE.asEuint64(amount));
    }

    function _isCompliant(
        address /*from*/,
        address /*to*/,
        euint64 /*encryptedAmount*/
    ) internal override returns (bool) {
        return compliantTransfer;
    }

    function _isForceCompliant(
        address /*from*/,
        address /*to*/,
        euint64 /*encryptedAmount*/
    ) internal override returns (bool) {
        return compliantForceTransfer;
    }

    function _validateHandleAllowance(bytes32 handle) internal view override onlyAdminOrAgent {}
}
