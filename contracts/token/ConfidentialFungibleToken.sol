// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { TFHE, einput, ebool, euint64 } from "fhevm/lib/TFHE.sol";
import { IConfidentialFungibleToken, IConfidentialFungibleTokenReceiver } from "./IConfidentialFungibleToken.sol";

function tryIncrease(euint64 oldValue, euint64 delta) returns (ebool success, euint64 updated) {
    if (euint64.unwrap(oldValue) == 0) {
        oldValue = TFHE.asEuint64(0);
    }

    euint64 newValue = TFHE.add(oldValue, delta);
    success = TFHE.ge(newValue, oldValue);
    updated = TFHE.select(success, newValue, oldValue);
}

function tryDecrease(euint64 oldValue, euint64 delta) returns (ebool success, euint64 updated) {
    success = TFHE.ge(oldValue, delta);
    updated = TFHE.select(success, TFHE.sub(oldValue, delta), oldValue);
}

abstract contract ConfidentialFungibleToken is IConfidentialFungibleToken {
    using TFHE for *;

    mapping(address holder => euint64) private _balances;
    mapping(address holder => mapping(address spender => uint48)) private _operators;
    euint64 private _totalSupply;
    string private _name;
    string private _symbol;
    string private _tokenURI;

    error InvalidReceiver(address receiver);
    error InvalidSender(address sender);
    error UnauthorizedSpender(address holder, address spender);
    error UnauthorizedUseOfEncryptedValue(euint64 amount, address user);

    constructor(string memory name_, string memory symbol_, string memory tokenURI_) {
        _name = name_;
        _symbol = symbol_;
        _tokenURI = tokenURI_;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return 9;
    }

    function tokenURI() public view virtual returns (string memory) {
        return _tokenURI;
    }

    function totalSupply() public view virtual returns (euint64) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual returns (euint64) {
        return _balances[account];
    }

    function isOperator(address holder, address spender) public view virtual returns (bool) {
        return block.timestamp <= _operators[holder][spender];
    }

    function setOperator(address operator, uint48 until) public virtual {
        _setOperator(msg.sender, operator, until);
    }

    function confidentialTransfer(
        address to,
        einput encryptedAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64 transferred) {
        return confidentialTransfer(to, encryptedAmount.asEuint64(inputProof));
    }

    function confidentialTransfer(address to, euint64 amount) public virtual returns (euint64 transferred) {
        require(amount.isAllowed(msg.sender), UnauthorizedUseOfEncryptedValue(amount, msg.sender));
        transferred = _transfer(msg.sender, to, amount);
        transferred.allowTransient(msg.sender);
    }

    function confidentialTransferFrom(
        address from,
        address to,
        einput encryptedAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64 transferred) {
        return confidentialTransferFrom(from, to, encryptedAmount.asEuint64(inputProof));
    }

    function confidentialTransferFrom(
        address from,
        address to,
        euint64 amount
    ) public virtual returns (euint64 transferred) {
        require(amount.isAllowed(msg.sender), UnauthorizedUseOfEncryptedValue(amount, msg.sender));
        require(isOperator(from, msg.sender), UnauthorizedSpender(from, msg.sender));
        transferred = _transfer(from, to, amount);
        transferred.allowTransient(msg.sender);
    }

    function confidentialTransferAndCall(
        address to,
        einput encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) public virtual returns (euint64 transferred) {
        return confidentialTransferAndCall(to, encryptedAmount.asEuint64(inputProof), data);
    }

    function confidentialTransferAndCall(
        address to,
        euint64 amount,
        bytes calldata data
    ) public virtual returns (euint64 transferred) {
        require(amount.isAllowed(msg.sender), UnauthorizedUseOfEncryptedValue(amount, msg.sender));
        transferred = _transferAndCall(msg.sender, to, amount, data);
        transferred.allowTransient(msg.sender);
    }

    function confidentialTransferFromAndCall(
        address from,
        address to,
        einput encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) public virtual returns (euint64 transferred) {
        return confidentialTransferFromAndCall(from, to, encryptedAmount.asEuint64(inputProof), data);
    }

    function confidentialTransferFromAndCall(
        address from,
        address to,
        euint64 amount,
        bytes calldata data
    ) public virtual returns (euint64 transferred) {
        require(amount.isAllowed(msg.sender), UnauthorizedUseOfEncryptedValue(amount, msg.sender));
        require(isOperator(from, msg.sender), UnauthorizedSpender(from, msg.sender));
        transferred = _transferAndCall(from, to, amount, data);
        transferred.allowTransient(msg.sender);
    }

    function discloseTransfer(
        address /*from*/,
        address /*to*/,
        euint64 /*amount*/,
        uint64 /*decryptedAmount*/,
        bytes calldata /*decryptedProof*/,
        bytes calldata /*inclusionProof*/
    ) public virtual {
        revert("not implemented yet");
    }

    function _setOperator(address holder, address operator, uint48 until) internal virtual {
        _operators[holder][operator] = until;
        emit OperatorSet(holder, operator, until);
    }

    function _mint(address to, euint64 amount) internal returns (euint64 transferred) {
        require(to != address(0), InvalidReceiver(address(0)));
        return _update(address(0), to, amount);
    }

    function _burn(address from, euint64 amount) internal returns (euint64 transferred) {
        require(from != address(0), InvalidSender(address(0)));
        return _update(from, address(0), amount);
    }

    function _transfer(address from, address to, euint64 amount) internal returns (euint64 transferred) {
        require(from != address(0), InvalidSender(address(0)));
        require(to != address(0), InvalidReceiver(address(0)));
        return _update(from, to, amount);
    }

    function _transferAndCall(
        address from,
        address to,
        euint64 amount,
        bytes calldata data
    ) internal returns (euint64 transferred) {
        // Try to transfer amount + replace input with actually transferred amount.
        euint64 sent = _transfer(from, to, amount);
        sent.allowTransient(to);

        // Perform callback
        transferred = _checkOnERC1363TransferReceived(msg.sender, from, to, sent, data).select(sent, 0.asEuint64());

        // Refund if success fails. refund should never fail
        _update(to, from, sent.sub(transferred));
    }

    function _update(address from, address to, euint64 amount) internal virtual returns (euint64 transferred) {
        ebool success;
        euint64 ptr;

        if (from == address(0)) {
            (success, ptr) = tryIncrease(_totalSupply, amount);
            ptr.allowThis();
            _totalSupply = ptr;
        } else {
            (success, ptr) = tryDecrease(_balances[from], amount);
            ptr.allowThis();
            ptr.allow(from);
            _balances[from] = ptr;
        }

        transferred = success.select(amount, 0.asEuint64());

        if (to == address(0)) {
            ptr = _totalSupply.sub(transferred);
            ptr.allowThis();
            _totalSupply = ptr;
        } else {
            ptr = _balances[to].add(transferred);
            ptr.allowThis();
            ptr.allow(to);
            _balances[to] = ptr;
        }

        if (from != address(0)) transferred.allow(from);
        if (to != address(0)) transferred.allow(to);
        transferred.allowThis();
        emit ConfidentialTransfer(from, to, transferred);
    }

    // TODO: move to utils library ?
    function _checkOnERC1363TransferReceived(
        address operator,
        address from,
        address to,
        euint64 value,
        bytes calldata data
    ) private returns (ebool) {
        if (to.code.length > 0) {
            try
                IConfidentialFungibleTokenReceiver(to).onConfidentialTransferReceived(operator, from, value, data)
            returns (ebool retval) {
                return retval;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert InvalidReceiver(to);
                } else {
                    assembly ("memory-safe") {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true.asEbool();
        }
    }
}
