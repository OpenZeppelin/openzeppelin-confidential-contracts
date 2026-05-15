// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, eaddress, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984} from "../../../token/ERC7984/ERC7984.sol";
import {HandleHelper} from "../../../utils/HandleHelper.sol";

// solhint-disable func-name-mixedcase
contract ERC7984Mock is ERC7984, ZamaEthereumConfig {
    using HandleHelper for euint64;

    address private immutable _OWNER;

    event EncryptedAmountCreated(euint64 amount);
    event EncryptedAddressCreated(eaddress addr);

    constructor(
        string memory name_,
        string memory symbol_,
        string memory tokenURI_
    ) ERC7984(name_, symbol_, tokenURI_) {
        _OWNER = msg.sender;
    }

    function createEncryptedAmount(uint64 amount) public returns (euint64 encryptedAmount) {
        FHE.allowThis(encryptedAmount = FHE.asEuint64(amount));
        FHE.allow(encryptedAmount, msg.sender);

        emit EncryptedAmountCreated(encryptedAmount);
    }

    function createEncryptedAddress(address addr) public returns (eaddress) {
        eaddress encryptedAddr = FHE.asEaddress(addr);
        FHE.allowThis(encryptedAddr);
        FHE.allow(encryptedAddr, msg.sender);

        emit EncryptedAddressCreated(encryptedAddr);
        return encryptedAddr;
    }

    function confidentialTransfer(address to, uint64 amount) public returns (euint64) {
        euint64 ciphertext = FHE.asEuint64(amount);
        FHE.allowTransient(ciphertext, msg.sender);

        return super.confidentialTransfer(to, ciphertext.toExternal(), msg.data[0:0]);
    }

    function _update(
        address from,
        address to,
        euint64 amount,
        bytes32 memo
    ) internal virtual override returns (euint64 transferred) {
        transferred = super._update(from, to, amount, memo);
        FHE.allow(confidentialTotalSupply(), _OWNER);
    }

    function $_mint(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public returns (euint64 transferred) {
        return _mint(to, FHE.fromExternal(encryptedAmount, inputProof), hex"");
    }

    function $_mint(address to, uint64 amount) public returns (euint64 transferred) {
        return _mint(to, FHE.asEuint64(amount), hex"");
    }

    function $_transfer(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public returns (euint64 transferred) {
        return _transfer(from, to, FHE.fromExternal(encryptedAmount, inputProof), hex"");
    }

    function $_transferAndCall(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) public returns (euint64 transferred) {
        return _transferAndCall(from, to, FHE.fromExternal(encryptedAmount, inputProof), data, hex"");
    }

    function $_burn(address from, uint64 amount) public returns (euint64 transferred) {
        return _burn(from, FHE.asEuint64(amount), hex"");
    }

    function $_burn(
        address from,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public returns (euint64 transferred) {
        return _burn(from, FHE.fromExternal(encryptedAmount, inputProof), hex"");
    }

    function $_update(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64 transferred) {
        return _update(from, to, FHE.fromExternal(encryptedAmount, inputProof), hex"");
    }
}
