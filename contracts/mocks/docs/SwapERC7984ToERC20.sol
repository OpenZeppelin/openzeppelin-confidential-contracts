// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC7984} from "../../interfaces/IERC7984.sol";

contract SwapConfidentialToERC20 {
    error SwapConfidentialToERC20InvalidGatewayRequest(uint256 requestId);

    mapping(uint256 requestId => address) private _receivers;
    IERC7984 private _fromToken;
    IERC20 private _toToken;

    constructor(IERC7984 fromToken, IERC20 toToken) {
        _fromToken = fromToken;
        _toToken = toToken;
    }

    function swapConfidentialToERC20(externalEuint64 encryptedInput, bytes memory inputProof) public {
        euint64 amount = FHE.fromExternal(encryptedInput, inputProof);
        FHE.allowTransient(amount, address(_fromToken));
        euint64 amountTransferred = _fromToken.confidentialTransferFrom(msg.sender, address(this), amount);

        bytes32[] memory cts = new bytes32[](1);
        cts[0] = euint64.unwrap(amountTransferred);
        uint256 requestID = FHE.requestDecryption(cts, this.finalizeSwap.selector);

        // register who is getting the tokens
        _receivers[requestID] = msg.sender;
    }

    function finalizeSwap(uint256 requestID, uint64 amount, bytes[] memory signatures) public virtual {
        FHE.checkSignatures(requestID, signatures);
        address to = _receivers[requestID];
        require(to != address(0), SwapConfidentialToERC20InvalidGatewayRequest(requestID));
        delete _receivers[requestID];

        if (amount != 0) {
            SafeERC20.safeTransfer(_toToken, to, amount);
        }
    }
}
