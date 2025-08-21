// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SepoliaConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984} from "../../token/ERC7984/ERC7984.sol";
// solhint-disable func-name-mixedcase
contract ERC7984Mock is ERC7984, SepoliaConfig {
    address private immutable _OWNER;

    constructor(
        string memory name_,
        string memory symbol_,
        string memory tokenURI_
    ) ERC7984(name_, symbol_, tokenURI_) {
        _OWNER = msg.sender;
    }

    function _update(address from, address to, euint64 amount) internal virtual override returns (euint64 transferred) {
        transferred = super._update(from, to, amount);
        FHE.allow(confidentialTotalSupply(), _OWNER);
    }

    function $_mint(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public returns (euint64 transferred) {
        return _mint(to, FHE.fromExternal(encryptedAmount, inputProof));
    }

    function $_transfer(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public returns (euint64 transferred) {
        return _transfer(from, to, FHE.fromExternal(encryptedAmount, inputProof));
    }

    function $_transferAndCall(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) public returns (euint64 transferred) {
        return _transferAndCall(from, to, FHE.fromExternal(encryptedAmount, inputProof), data);
    }

    function $_burn(
        address from,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public returns (euint64 transferred) {
        return _burn(from, FHE.fromExternal(encryptedAmount, inputProof));
    }

    function $_update(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64 transferred) {
        return _update(from, to, FHE.fromExternal(encryptedAmount, inputProof));
    }
}
