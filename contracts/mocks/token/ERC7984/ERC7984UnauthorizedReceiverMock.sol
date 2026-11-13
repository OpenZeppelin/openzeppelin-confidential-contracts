// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984Receiver} from "../../../interfaces/IERC7984Receiver.sol";

/// @dev Receiver mock that can return an `ebool` it has no FHE ACL allowance for.
///
/// Used to assert that {ERC7984Utils-checkOnTransferReceived} rejects callback return
/// values the recipient is not allowed to use.
contract ERC7984UnauthorizedReceiverMock is IERC7984Receiver, ZamaEthereumConfig {
    address private immutable _TOKEN;

    ebool private _returnValue;

    constructor(address token) {
        _TOKEN = token;
    }

    /// @dev Creates and stores an encrypted bool with persistent ACL for this contract and `_TOKEN`.
    function createReturnValue(bool value) external {
        ebool result = FHE.asEbool(value);
        FHE.allowThis(result);
        FHE.allow(result, _TOKEN);
        _returnValue = result;
    }

    /// @dev Stores `value` without granting this contract any ACL on it.
    function setReturnValue(ebool value) external {
        _returnValue = value;
    }

    function getReturnValue() external view returns (ebool) {
        return _returnValue;
    }

    function onConfidentialTransferReceived(address, address, euint64, bytes calldata) external view returns (ebool) {
        return _returnValue;
    }
}
