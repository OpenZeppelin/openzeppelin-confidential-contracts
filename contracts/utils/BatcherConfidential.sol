// SPDX-License-Identifier: MIT

import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {ERC7984ERC20Wrapper} from "../token/ERC7984/extensions/ERC7984ERC20Wrapper.sol";

pragma solidity ^0.8.24;

contract BatcherConfidential {
    ERC7984ERC20Wrapper private _fromToken;
    ERC7984ERC20Wrapper private _toToken;
    mapping(uint256 => Batch) private _batches;

    struct Batch {
        euint64 confidentialAmount;
    }

    function join() public {}

    function exit() public {}

    function dispatchBatch(uint256 batchId) public {
        fromToken().unwrap(address(this), address(this), _batches[batchId].confidentialAmount);
    }

    function dispatchBatchCallback(uint64 burntAmountCleartext, bytes calldata decryptionProof) public {
        fromToken().finalizeUnwrap(FHE.asEuint64(0), burntAmountCleartext, decryptionProof);
    }

    function finalizeBatch() public {}

    function fromToken() public view returns (ERC7984ERC20Wrapper) {
        return _fromToken;
    }

    function toToken() public view returns (ERC7984ERC20Wrapper) {
        return _toToken;
    }
}
