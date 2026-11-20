// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, eaddress, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {Calldata} from "@openzeppelin/contracts/utils/Calldata.sol";
import {ERC7984} from "./../../../token/ERC7984/ERC7984.sol";
import {HandleHelper} from "./../../../utils/HandleHelper.sol";

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

        return super.confidentialTransfer(to, ciphertext.toExternal(), Calldata.emptyBytes());
    }

    function confidentialTransferAndCall(address to, uint64 amount, bytes calldata data) public returns (euint64) {
        euint64 ciphertext = FHE.asEuint64(amount);
        FHE.allowTransient(ciphertext, msg.sender);

        return super.confidentialTransferAndCall(to, ciphertext.toExternal(), Calldata.emptyBytes(), data);
    }

    function _update(
        address operator,
        address from,
        address to,
        euint64 amount,
        bytes32 memo,
        bool bypassRestrictions
    ) internal virtual override returns (euint64 transferred) {
        transferred = super._update(operator, from, to, amount, memo, bypassRestrictions);
        FHE.allow(confidentialTotalSupply(), _OWNER);
    }

    function $_update(
        address from,
        address to,
        uint64 amount,
        bool bypassRestrictions
    ) public returns (euint64 transferred) {
        return _update(msg.sender, from, to, FHE.asEuint64(amount), bytes32(0), bypassRestrictions);
    }

    function $_mint(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public returns (euint64 transferred) {
        return _mint(msg.sender, to, FHE.fromExternal(encryptedAmount, inputProof), bytes32(0));
    }

    function $_mint(address to, uint64 amount) public returns (euint64 transferred) {
        return _mint(msg.sender, to, FHE.asEuint64(amount), bytes32(0));
    }

    function $_transfer(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public returns (euint64 transferred) {
        return _transfer(msg.sender, from, to, FHE.fromExternal(encryptedAmount, inputProof), bytes32(0));
    }

    function $_transferAndCall(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) public returns (euint64 transferred) {
        return _transferAndCall(msg.sender, from, to, FHE.fromExternal(encryptedAmount, inputProof), data, bytes32(0));
    }

    function $_burn(address from, uint64 amount) public returns (euint64 transferred) {
        return _burn(msg.sender, from, FHE.asEuint64(amount), bytes32(0));
    }

    function $_burn(
        address from,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public returns (euint64 transferred) {
        return _burn(msg.sender, from, FHE.fromExternal(encryptedAmount, inputProof), bytes32(0));
    }

    function $_update(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof,
        bool bypassRestrictions
    ) public virtual returns (euint64 transferred) {
        return
            _update(
                msg.sender,
                from,
                to,
                FHE.fromExternal(encryptedAmount, inputProof),
                bytes32(0),
                bypassRestrictions
            );
    }
}
