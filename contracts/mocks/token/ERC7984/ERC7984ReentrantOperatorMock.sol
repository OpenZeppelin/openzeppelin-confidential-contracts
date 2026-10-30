// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984} from "../../../interfaces/IERC7984.sol";
import {IERC7984Receiver} from "../../../interfaces/IERC7984Receiver.sol";

/// @dev Operator that spends from `holder` again, as the same operator, from within its own transfer callback.
contract ERC7984ReentrantOperatorMock is IERC7984Receiver, ZamaEthereumConfig {
    externalEuint64 private _reentrantAmount;
    bytes private _inputProof;
    bool private _reentered;

    /// @dev Limit seen from within the callback, and whether the operator and the holder could access it then.
    euint64 public inFlightLimit;
    bool public operatorCouldAccessInFlightLimit;
    bool public holderCouldAccessInFlightLimit;

    function spend(
        IERC7984 token,
        address holder,
        externalEuint64 amount,
        externalEuint64 reentrantAmount,
        bytes calldata inputProof
    ) external {
        _reentrantAmount = reentrantAmount;
        _inputProof = inputProof;
        token.confidentialTransferFromAndCall(holder, address(this), amount, inputProof, "");
    }

    function onConfidentialTransferReceived(address, address from, euint64, bytes calldata) external returns (ebool) {
        if (!_reentered) {
            _reentered = true;

            (, inFlightLimit) = IERC7984(msg.sender).isOperator(from, address(this));
            operatorCouldAccessInFlightLimit = FHE.isAllowed(inFlightLimit, address(this));
            holderCouldAccessInFlightLimit = FHE.isAllowed(inFlightLimit, from);

            IERC7984(msg.sender).confidentialTransferFrom(from, address(this), _reentrantAmount, _inputProof);
        }

        ebool returnVal = FHE.asEbool(true);
        FHE.allowTransient(returnVal, msg.sender);
        return returnVal;
    }
}
