// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC7984} from "../../interfaces/IERC7984.sol";

contract SwapERC7984ToERC20 {
    error SwapERC7984ToERC20InvalidFinalization(euint64 amount);

    mapping(euint64 amount => address) private _receivers;
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

        FHE.makePubliclyDecryptable(amountTransferred);
        _receivers[amountTransferred] = msg.sender;
    }

    function finalizeSwap(euint64 amount, uint64 cleartextAmount, bytes calldata decryptionProof) public virtual {
        bytes32[] memory handlesList = new bytes32[](1);
        handlesList[0] = euint64.unwrap(amount);

        FHE.verifySignatures(handlesList, abi.encode(cleartextAmount), decryptionProof);
        address to = _receivers[amount];
        require(to != address(0), SwapERC7984ToERC20InvalidFinalization(amount));
        delete _receivers[amount];

        if (cleartextAmount != 0) {
            SafeERC20.safeTransfer(_toToken, to, cleartextAmount);
        }
    }
}
