// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {Impl} from "@fhevm/solidity/lib/Impl.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ConfidentialFungibleToken} from "../../token/ConfidentialFungibleToken.sol";
import {ERC7984Freezable} from "../../token/extensions/ERC7984Freezable.sol";
import {HandleAccessManager} from "../../utils/HandleAccessManager.sol";

// solhint-disable func-name-mixedcase
contract ERC7984FreezableMock is ERC7984Freezable, AccessControl, HandleAccessManager, SepoliaConfig {
    bytes32 public constant FREEZER_ROLE = keccak256("FREEZER_ROLE");

    error UnallowedHandleAccess(bytes32 handle, address account);

    constructor(
        string memory name,
        string memory symbol,
        string memory tokenUri,
        address freezer
    ) ConfidentialFungibleToken(name, symbol, tokenUri) {
        _grantRole(FREEZER_ROLE, freezer);
    }

    function confidentialAvailableAccess(address account) public {
        getHandleAllowance(euint64.unwrap(confidentialAvailable(account)), account, true);
    }

    function _validateHandleAllowance(bytes32 handle) internal view override {}

    function $_mint(address to, uint64 amount) public returns (euint64 transferred) {
        return _mint(to, FHE.asEuint64(amount));
    }

    function _checkFreezer() internal override onlyRole(FREEZER_ROLE) {}
}
