// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { TFHE, einput, ebool, euint64 } from "fhevm/lib/TFHE.sol";
import { Gateway } from "fhevm/gateway/lib/Gateway.sol";

import { IConfidentialFungibleToken } from "../interfaces/IConfidentialFungibleToken.sol";
import { ConfidentialFungibleTokenUtils } from "./utils/ConfidentialFungibleTokenUtils.sol";
import { TFHESafeMath } from "../utils/TFHESafeMath.sol";

/**
 * @dev Reference implementation for {IConfidentialFungibleToken}.
 *
 * This contract implements a fungible token where balances and transfers are encrypted using the Zama fhEVM,
 * providing confidentiality to users. Token amounts are stored as encrypted, unsigned integers (`euint64`)
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
    mapping(address holder => euint64) private _balances;
    mapping(address holder => mapping(address spender => uint48)) private _operators;
    mapping(uint256 requestId => euint64 encryptedAmount) private _requestHandles;
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

    /// @dev The holder `holder` is trying to send tokens but has a balance of 0.
    error ConfidentialFungibleTokenZeroBalance(address holder);

    /**
     * @dev The caller `user` does not have access to the encrypted amount `amount`.
     *
     * NOTE: Try using the equivalent transfer function with an input proof.
     */
    error ConfidentialFungibleTokenUnauthorizedUseOfEncryptedAmount(euint64 amount, address user);

    /// @dev The given caller `caller` is not authorized for the current operation.
    error ConfidentialFungibleTokenUnauthorizedCaller(address caller);

    /// @dev The given gateway request ID `requestId` is invalid.
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
        return holder == spender || block.timestamp <= _operators[holder][spender];
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
    ) public virtual returns (euint64) {
        return _transfer(msg.sender, to, TFHE.asEuint64(encryptedAmount, inputProof));
    }

    /// @inheritdoc IConfidentialFungibleToken
    function confidentialTransfer(address to, euint64 amount) public virtual returns (euint64) {
        require(
            TFHE.isAllowed(amount, msg.sender),
            ConfidentialFungibleTokenUnauthorizedUseOfEncryptedAmount(amount, msg.sender)
        );
        return _transfer(msg.sender, to, amount);
    }

    /// @inheritdoc IConfidentialFungibleToken
    function confidentialTransferFrom(
        address from,
        address to,
        einput encryptedAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64 transferred) {
        require(isOperator(from, msg.sender), ConfidentialFungibleTokenUnauthorizedSpender(from, msg.sender));
        transferred = _transfer(from, to, TFHE.asEuint64(encryptedAmount, inputProof));
        TFHE.allowTransient(transferred, msg.sender);
    }

    /// @inheritdoc IConfidentialFungibleToken
    function confidentialTransferFrom(
        address from,
        address to,
        euint64 amount
    ) public virtual returns (euint64 transferred) {
        require(
            TFHE.isAllowed(amount, msg.sender),
            ConfidentialFungibleTokenUnauthorizedUseOfEncryptedAmount(amount, msg.sender)
        );
        require(isOperator(from, msg.sender), ConfidentialFungibleTokenUnauthorizedSpender(from, msg.sender));
        transferred = _transfer(from, to, amount);
        TFHE.allowTransient(transferred, msg.sender);
    }

    /// @inheritdoc IConfidentialFungibleToken
    function confidentialTransferAndCall(
        address to,
        einput encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) public virtual returns (euint64 transferred) {
        transferred = _transferAndCall(msg.sender, to, TFHE.asEuint64(encryptedAmount, inputProof), data);
        TFHE.allowTransient(transferred, msg.sender);
    }

    /// @inheritdoc IConfidentialFungibleToken
    function confidentialTransferAndCall(
        address to,
        euint64 amount,
        bytes calldata data
    ) public virtual returns (euint64 transferred) {
        require(
            TFHE.isAllowed(amount, msg.sender),
            ConfidentialFungibleTokenUnauthorizedUseOfEncryptedAmount(amount, msg.sender)
        );
        transferred = _transferAndCall(msg.sender, to, amount, data);
        TFHE.allowTransient(transferred, msg.sender);
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
        transferred = _transferAndCall(from, to, TFHE.asEuint64(encryptedAmount, inputProof), data);
        TFHE.allowTransient(transferred, msg.sender);
    }

    /// @inheritdoc IConfidentialFungibleToken
    function confidentialTransferFromAndCall(
        address from,
        address to,
        euint64 amount,
        bytes calldata data
    ) public virtual returns (euint64 transferred) {
        require(
            TFHE.isAllowed(amount, msg.sender),
            ConfidentialFungibleTokenUnauthorizedUseOfEncryptedAmount(amount, msg.sender)
        );
        require(isOperator(from, msg.sender), ConfidentialFungibleTokenUnauthorizedSpender(from, msg.sender));
        transferred = _transferAndCall(from, to, amount, data);
        TFHE.allowTransient(transferred, msg.sender);
    }

    /**
     * @dev Discloses an encrypted amount `encryptedAmount` publicly via an {EncryptedAmountDisclosed}
     * event. The caller and this contract must be authorized to use the encrypted amount on the ACL.
     *
     * NOTE: This is an asynchronous operation where the actual decryption happens off-chain and
     * {finalizeDiscloseEncryptedAmount} is called with the result.
     */
    function discloseEncryptedAmount(euint64 encryptedAmount) public virtual {
        require(
            TFHE.isAllowed(encryptedAmount, msg.sender) && TFHE.isAllowed(encryptedAmount, address(this)),
            ConfidentialFungibleTokenUnauthorizedUseOfEncryptedAmount(encryptedAmount, msg.sender)
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

    /// @dev May only be called by the gateway contract. Finalizes a disclose encrypted amount request.
    function finalizeDiscloseEncryptedAmount(uint256 requestId, uint64 amount) public virtual onlyGateway {
        euint64 requestHandle = _requestHandles[requestId];
        require(euint64.unwrap(requestHandle) != 0, ConfidentialFungibleTokenInvalidGatewayRequest(requestId));
        emit EncryptedAmountDisclosed(requestHandle, amount);

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

        // Perform callback
        transferred = TFHE.select(
            ConfidentialFungibleTokenUtils.checkOnERC1363TransferReceived(msg.sender, from, to, sent, data),
            sent,
            TFHE.asEuint64(0)
        );

        // Refund if success fails. refund should never fail
        _update(to, from, TFHE.sub(sent, transferred));
    }

    function _update(address from, address to, euint64 amount) internal virtual returns (euint64 transferred) {
        ebool success;
        euint64 ptr;

        if (from == address(0)) {
            (success, ptr) = TFHESafeMath.tryIncrease(_totalSupply, amount);
            TFHE.allowThis(ptr);
            _totalSupply = ptr;
        } else {
            euint64 fromBalance = _balances[from];
            require(euint64.unwrap(fromBalance) != 0, ConfidentialFungibleTokenZeroBalance(from));
            (success, ptr) = TFHESafeMath.tryDecrease(fromBalance, amount);
            TFHE.allowThis(ptr);
            TFHE.allow(ptr, from);
            _balances[from] = ptr;
        }

        transferred = TFHE.select(success, amount, TFHE.asEuint64(0));

        if (to == address(0)) {
            ptr = TFHE.sub(_totalSupply, transferred);
            TFHE.allowThis(ptr);
            _totalSupply = ptr;
        } else {
            ptr = TFHE.add(_balances[to], transferred);
            TFHE.allowThis(ptr);
            TFHE.allow(ptr, to);
            _balances[to] = ptr;
        }

        if (from != address(0)) TFHE.allow(transferred, from);
        if (to != address(0)) TFHE.allow(transferred, to);
        TFHE.allowThis(transferred);
        emit ConfidentialTransfer(from, to, transferred);
    }
}
