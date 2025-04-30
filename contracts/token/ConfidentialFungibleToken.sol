// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { TFHE, einput, ebool, euint64 } from "fhevm/lib/TFHE.sol";
import { Gateway } from "fhevm/gateway/lib/Gateway.sol";
import { IConfidentialFungibleToken } from "../interfaces/IConfidentialFungibleToken.sol";
import { IConfidentialFungibleTokenReceiver } from "../interfaces/IConfidentialFungibleTokenReceiver.sol";

function tryIncrease(euint64 oldValue, euint64 delta) returns (ebool success, euint64 updated) {
    if (euint64.unwrap(oldValue) == 0) {
        success = TFHE.asEbool(true);
        updated = delta;
    } else {
        euint64 newValue = TFHE.add(oldValue, delta);
        success = TFHE.ge(newValue, oldValue);
        updated = TFHE.select(success, newValue, oldValue);
    }
}

function tryDecrease(euint64 oldValue, euint64 delta) returns (ebool success, euint64 updated) {
    success = TFHE.ge(oldValue, delta);
    updated = TFHE.select(success, TFHE.sub(oldValue, delta), oldValue);
}

/**
 * @dev Reference implementation for {IConfidentialFungibleToken}.
 *
 * This contract implements a fungible token where balances and transfers are encrypted using the Zama fhEVM,
 * providing confidentiality to users. Token amounts are stored as encrypted, unsigned integers (euint64)
 * that can only be decrypted by authorized parties.
 *
 * Key features:
 *
 * - All balances are encrypted
 * - Transfers happen without revealing amounts
 * - Support for operators (delegated transfer capabilities with time bounds)
 * - ERC1363-like functionality with transfer-and-call pattern
 * - Safe overflow/underflow handling for FHE operations
 */
abstract contract ConfidentialFungibleToken is IConfidentialFungibleToken {
    using TFHE for *;

    mapping(address holder => euint64) private _balances;
    mapping(address holder => mapping(address spender => uint48)) private _operators;
    mapping(uint256 requestId => euint64 encryptedValue) private _requestHandles;
    euint64 private _totalSupply;
    string private _name;
    string private _symbol;
    string private _tokenURI;

    /// @dev The given receiver `receiver` is invalid for transfers.
    error ConfidentialFungibleTokenInvalidReceiver(address receiver);

    /// @dev The given sender `sender` is invalid for transfers.
    error ConfidentialFungibleTokenInvalidSender(address sender);

    /// @dev The given holder `holder` is not authorized to spend on behalf of `spender`.
    error ConfidentialFungibleTokenUnauthorizedSpender(address holder, address spender);

    /// @dev The `holder` is trying to send tokens but has a balance of 0.
    error ConfidentialFungibleTokenZeroBalance(address holder);

    /**
     * @dev The caller `user` does not have access to the encrypted value `amount`.
     *
     * NOTE: Try using the equivalent transfer function with an input proof.
     */
    error ConfidentialFungibleTokenUnauthorizedUseOfEncryptedValue(euint64 amount, address user);

    error ConfidentialFungibleTokenUnauthorizedCaller(address caller);

    error ConfidentialFungibleTokenInvalidGatewayRequest(uint256 requestId);

    modifier onlyGateway() {
        require(
            msg.sender == Gateway.gatewayContractAddress(),
            ConfidentialFungibleTokenUnauthorizedCaller(msg.sender)
        );
        _;
    }

    constructor(string memory name_, string memory symbol_, string memory tokenURI_) {
        _name = name_;
        _symbol = symbol_;
        _tokenURI = tokenURI_;
    }

    /// @inheritdoc IConfidentialFungibleToken
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /// @inheritdoc IConfidentialFungibleToken
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /// @inheritdoc IConfidentialFungibleToken
    function decimals() public view virtual returns (uint8) {
        return 9;
    }

    /// @inheritdoc IConfidentialFungibleToken
    function tokenURI() public view virtual returns (string memory) {
        return _tokenURI;
    }

    /// @inheritdoc IConfidentialFungibleToken
    function totalSupply() public view virtual returns (euint64) {
        return _totalSupply;
    }

    /// @inheritdoc IConfidentialFungibleToken
    function balanceOf(address account) public view virtual returns (euint64) {
        return _balances[account];
    }

    /// @inheritdoc IConfidentialFungibleToken
    function isOperator(address holder, address spender) public view virtual returns (bool) {
        return block.timestamp <= _operators[holder][spender];
    }

    /// @inheritdoc IConfidentialFungibleToken
    function setOperator(address operator, uint48 until) public virtual {
        _setOperator(msg.sender, operator, until);
    }

    /// @inheritdoc IConfidentialFungibleToken
    function confidentialTransfer(
        address to,
        einput encryptedAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64 transferred) {
        transferred = _transfer(msg.sender, to, encryptedAmount.asEuint64(inputProof));
        transferred.allowTransient(msg.sender);
    }

    /// @inheritdoc IConfidentialFungibleToken
    function confidentialTransfer(address to, euint64 amount) public virtual returns (euint64 transferred) {
        require(
            amount.isAllowed(msg.sender),
            ConfidentialFungibleTokenUnauthorizedUseOfEncryptedValue(amount, msg.sender)
        );
        transferred = _transfer(msg.sender, to, amount);
        transferred.allowTransient(msg.sender);
    }

    /// @inheritdoc IConfidentialFungibleToken
    function confidentialTransferFrom(
        address from,
        address to,
        einput encryptedAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64 transferred) {
        require(isOperator(from, msg.sender), ConfidentialFungibleTokenUnauthorizedSpender(from, msg.sender));
        transferred = _transfer(from, to, encryptedAmount.asEuint64(inputProof));
        transferred.allowTransient(msg.sender);
    }

    /// @inheritdoc IConfidentialFungibleToken
    function confidentialTransferFrom(
        address from,
        address to,
        euint64 amount
    ) public virtual returns (euint64 transferred) {
        require(
            amount.isAllowed(msg.sender),
            ConfidentialFungibleTokenUnauthorizedUseOfEncryptedValue(amount, msg.sender)
        );
        require(isOperator(from, msg.sender), ConfidentialFungibleTokenUnauthorizedSpender(from, msg.sender));
        transferred = _transfer(from, to, amount);
        transferred.allowTransient(msg.sender);
    }

    /// @inheritdoc IConfidentialFungibleToken
    function confidentialTransferAndCall(
        address to,
        einput encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) public virtual returns (euint64 transferred) {
        transferred = _transferAndCall(msg.sender, to, encryptedAmount.asEuint64(inputProof), data);
        transferred.allowTransient(msg.sender);
    }

    /// @inheritdoc IConfidentialFungibleToken
    function confidentialTransferAndCall(
        address to,
        euint64 amount,
        bytes calldata data
    ) public virtual returns (euint64 transferred) {
        require(
            amount.isAllowed(msg.sender),
            ConfidentialFungibleTokenUnauthorizedUseOfEncryptedValue(amount, msg.sender)
        );
        transferred = _transferAndCall(msg.sender, to, amount, data);
        transferred.allowTransient(msg.sender);
    }

    /// @inheritdoc IConfidentialFungibleToken
    function confidentialTransferFromAndCall(
        address from,
        address to,
        einput encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) public virtual returns (euint64 transferred) {
        require(isOperator(from, msg.sender), ConfidentialFungibleTokenUnauthorizedSpender(from, msg.sender));
        transferred = _transferAndCall(from, to, encryptedAmount.asEuint64(inputProof), data);
        transferred.allowTransient(msg.sender);
    }

    /// @inheritdoc IConfidentialFungibleToken
    function confidentialTransferFromAndCall(
        address from,
        address to,
        euint64 amount,
        bytes calldata data
    ) public virtual returns (euint64 transferred) {
        require(
            amount.isAllowed(msg.sender),
            ConfidentialFungibleTokenUnauthorizedUseOfEncryptedValue(amount, msg.sender)
        );
        require(isOperator(from, msg.sender), ConfidentialFungibleTokenUnauthorizedSpender(from, msg.sender));
        transferred = _transferAndCall(from, to, amount, data);
        transferred.allowTransient(msg.sender);
    }

    function discloseEncryptedAmount(euint64 encryptedAmount) public virtual {
        require(
            encryptedAmount.isAllowed(msg.sender) && encryptedAmount.isAllowed(address(this)),
            ConfidentialFungibleTokenUnauthorizedUseOfEncryptedValue(encryptedAmount, msg.sender)
        );

        uint256[] memory cts = new uint256[](1);
        cts[0] = euint64.unwrap(encryptedAmount);
        uint256 requestID = Gateway.requestDecryption(
            cts,
            this.finalizeDiscloseEncryptedAmount.selector,
            0,
            block.timestamp + 1 days,
            false
        );
        _requestHandles[requestID] = encryptedAmount;
    }

    function finalizeDiscloseEncryptedAmount(uint256 requestId, uint64 amount) public virtual onlyGateway {
        require(
            euint64.unwrap(_requestHandles[requestId]) != 0,
            ConfidentialFungibleTokenInvalidGatewayRequest(requestId)
        );
        emit EncryptedAmountDisclosed(_requestHandles[requestId], amount);

        _requestHandles[requestId] = euint64.wrap(0);
    }

    function _setOperator(address holder, address operator, uint48 until) internal virtual {
        _operators[holder][operator] = until;
        emit OperatorSet(holder, operator, until);
    }

    function _mint(address to, euint64 amount) internal returns (euint64 transferred) {
        require(to != address(0), ConfidentialFungibleTokenInvalidReceiver(address(0)));
        return _update(address(0), to, amount);
    }

    function _burn(address from, euint64 amount) internal returns (euint64 transferred) {
        require(from != address(0), ConfidentialFungibleTokenInvalidSender(address(0)));
        return _update(from, address(0), amount);
    }

    function _transfer(address from, address to, euint64 amount) internal returns (euint64 transferred) {
        require(from != address(0), ConfidentialFungibleTokenInvalidSender(address(0)));
        require(to != address(0), ConfidentialFungibleTokenInvalidReceiver(address(0)));
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
            require(euint64.unwrap(_balances[from]) != 0, ConfidentialFungibleTokenZeroBalance(from));
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
                    revert ConfidentialFungibleTokenInvalidReceiver(to);
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
