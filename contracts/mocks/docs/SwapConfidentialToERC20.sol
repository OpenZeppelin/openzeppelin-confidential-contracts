// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TFHE, einput, euint64} from "fhevm/lib/TFHE.sol";
import {Gateway} from "fhevm/gateway/lib/Gateway.sol";
import {GatewayCaller} from "fhevm/gateway/GatewayCaller.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IConfidentialFungibleToken} from "../../interfaces/IConfidentialFungibleToken.sol";

contract SwapConfidentialToERC20 is GatewayCaller {
    using TFHE for *;

    error SwapConfidentialToERC20InvalidGatewayRequest(uint256 requestId);

    mapping(uint256 requestId => address) private _receivers;
    IConfidentialFungibleToken private _fromToken;
    IERC20 private _toToken;

    constructor(IConfidentialFungibleToken fromToken, IERC20 toToken) {
        _fromToken = fromToken;
        _toToken = toToken;
    }

    function swapConfidentialToERC20(einput encryptedInput, bytes memory inputProof) public {
        euint64 amount = encryptedInput.asEuint64(inputProof);
        amount.allowTransient(address(_fromToken));
        euint64 amountTransferred = _fromToken.confidentialTransferFrom(msg.sender, address(this), amount);

        uint256[] memory cts = new uint256[](1);
        cts[0] = euint64.unwrap(amountTransferred);
        uint256 requestID = Gateway.requestDecryption(
            cts,
            this.finalizeSwap.selector,
            0,
            block.timestamp + 1 days, // Max delay is 1 day
            false
        );

        // register who is getting the tokens
        _receivers[requestID] = msg.sender;
    }

    function finalizeSwap(uint256 requestID, uint64 amount) public virtual onlyGateway {
        address to = _receivers[requestID];
        require(to != address(0), SwapConfidentialToERC20InvalidGatewayRequest(requestID));
        delete _receivers[requestID];

        if (amount != 0) {
            SafeERC20.safeTransfer(_toToken, to, amount);
        }
    }
}
