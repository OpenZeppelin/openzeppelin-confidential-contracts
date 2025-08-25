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

    constructor(string memory name, string memory symbol, string memory tokenUri) ERC7984Rwa(name, symbol, tokenUri) {}

    function $_setCompliantTransfer() public {
        compliantTransfer = true;
    }

    function $_unsetCompliantTransfer() public {
        compliantTransfer = false;
    }

    function $_mint(address to, uint64 amount) public returns (euint64 transferred) {
        return _mint(to, FHE.asEuint64(amount));
    }

    function _isCompliantTransfer(
        address /*from*/,
        address /*to*/,
        euint64 /*encryptedAmount*/
    ) internal override returns (bool) {
        return compliantTransfer;
    }

    // TODO: Remove all below
    function confidentialAvailable(address account) public override returns (euint64) {
        (ebool success, euint64 unfrozen) = FHESafeMath.tryDecrease(
            confidentialBalanceOf(account),
            confidentialFrozen(account)
        );
        unfrozen = FHE.select(success, unfrozen, FHE.asEuint64(0));
        FHE.allowThis(unfrozen);
        return unfrozen;
    }
    function confidentialFrozen(address account) public view override returns (euint64) {
        return _frozenBalances[account];
    }
    function setConfidentialFrozen(
        address account,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public override {
        return setConfidentialFrozen(account, FHE.fromExternal(encryptedAmount, inputProof));
    }
    function setConfidentialFrozen(address account, euint64 encryptedAmount) public override {
        FHE.allowThis(_frozenBalances[account] = encryptedAmount);
    }

    function _validateHandleAllowance(bytes32 handle) internal view override onlyAdminOrAgent {}
}
