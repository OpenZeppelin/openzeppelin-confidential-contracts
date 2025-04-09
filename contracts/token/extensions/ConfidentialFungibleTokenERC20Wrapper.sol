// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { TFHE, euint64 } from "fhevm/lib/TFHE.sol";
import { Gateway } from "fhevm/gateway/lib/Gateway.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC1363Receiver } from "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeCast } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ConfidentialFungibleToken } from "../ConfidentialFungibleToken.sol";

abstract contract ConfidentialFungibleTokenERC20Wrapper is ConfidentialFungibleToken, IERC1363Receiver {
    using TFHE for *;
    using SafeCast for *;

    IERC20 public immutable token;

    mapping(uint256 decryptionRequest => address) private _receivers;

    error UnauthorizedCaller(address);
    error InvalidUnwrapRequest(uint256);

    modifier onlyGateway() {
        require(msg.sender == Gateway.gatewayContractAddress(), UnauthorizedCaller(msg.sender));
        _;
    }

    constructor(IERC20 token_) {
        token = token_;
    }

    function onTransferReceived(
        address /*operator*/,
        address from,
        uint256 value,
        bytes calldata data
    ) public virtual returns (bytes4) {
        require(address(token) == msg.sender, UnauthorizedCaller(msg.sender));
        address to = data.length < 20 ? from : address(bytes20(data));
        _mint(to, value.asUint64().asEuint64());
        return IERC1363Receiver.onTransferReceived.selector;
    }

    function wrap(address to, uint256 amount) public virtual {
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);
        _mint(to, value.asUint64().asEuint64());
    }

    function unwrap(address from, address to, einput encryptedAmount, bytes calldata inputProof) public virtual {
        unwrap(from, to, encryptedAmount.asEuint64(inputProof));
    }

    function unwrap(address from, address to, euint64 amount) public virtual {
        require(amount.isAllowed(msg.sender), UnauthorizedUseOfEncryptedValue(amount, msg.sender));
        require(from == msg.sender || isOperator(from, msg.sender), UnauthorizedSpender(from, msg.sender));

        // try to burn, see how much we actually got
        euint64 burntAmount = _burn(from, amount);

        // decrypt that burntAmount
        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(burntAmount);
        uint256 requestID = Gateway.requestDecryption(
            cts,
            this.finalizeUnwrap.selector,
            0,
            block.timestamp + 3600,
            false
        ); // max delay ?

        // register who is getting the tokens
        _receivers[requestID] = to;
    }

    function finalizeUnwrap(uint256 requestID, uint64 amount) public virtual onlyGateway {
        address to = _receivers[requestID];
        require(to != address(0), InvalidUnwrapRequest(requestID));
        delete _receivers[requestID];

        SafeERC20.safeTransfer(token, to, amount);
    }
}
