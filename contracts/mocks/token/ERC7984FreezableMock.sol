// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC7984} from "../../token/ERC7984/ERC7984.sol";
import {ERC7984Freezable} from "../../token/ERC7984/extensions/ERC7984Freezable.sol";
import {HandleAccessManager} from "../../utils/HandleAccessManager.sol";
import {ERC7984Mock} from "./ERC7984Mock.sol";

contract ERC7984FreezableMock is ERC7984Mock, ERC7984Freezable, AccessControl, HandleAccessManager {
    bytes32 public constant FREEZER_ROLE = keccak256("FREEZER_ROLE");

    error UnallowedHandleAccess(bytes32 handle, address account);

    constructor(
        string memory name,
        string memory symbol,
        string memory tokenUri,
        address freezer
    ) ERC7984Mock(name, symbol, tokenUri) {
        _grantRole(FREEZER_ROLE, freezer);
    }

    function _update(
        address from,
        address to,
        euint64 amount
    ) internal virtual override(ERC7984Mock, ERC7984Freezable) returns (euint64) {
        return super._update(from, to, amount);
    }

    // solhint-disable-next-line func-name-mixedcase
    function $_setConfidentialFrozen(
        address account,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual {
        _setConfidentialFrozen(account, FHE.fromExternal(encryptedAmount, inputProof));
    }

    function confidentialAvailableAccess(address account) public {
        euint64 available = confidentialAvailable(account);
        FHE.allowThis(available);
        getHandleAllowance(euint64.unwrap(available), account, true);
    }

    function _validateHandleAllowance(bytes32 handle) internal view override {}

    function _checkFreezer() internal override onlyRole(FREEZER_ROLE) {}
}
