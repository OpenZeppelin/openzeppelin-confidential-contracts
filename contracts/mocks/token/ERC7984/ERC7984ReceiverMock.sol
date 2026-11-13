// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, ebool, euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984Receiver} from "../../../interfaces/IERC7984Receiver.sol";
import {ERC7984HookModuleMock} from "./utils/ERC7984HookModuleMock.sol";

contract ERC7984ReceiverMock is IERC7984Receiver, ZamaEthereumConfig {
    event ConfidentialTransferCallback(bool success);

    error InvalidInput(uint8 input);

    /// Data should contain a success boolean (plaintext). Revert if not.
    function onConfidentialTransferReceived(address, address, euint64, bytes calldata data) external returns (ebool) {
        uint8 input = abi.decode(data, (uint8));

        if (input > 1) revert InvalidInput(input);

        bool success = input == 1;
        emit ConfidentialTransferCallback(success);

        ebool returnVal = FHE.asEbool(success);
        FHE.allowTransient(returnVal, msg.sender);

        return returnVal;
    }
}

contract ERC7984ReceiverMutatorMock is IERC7984Receiver, ZamaEthereumConfig {
    enum Action {
        BLOCK_SELF,
        FREEZE_SELF,
        SET_MODULE_NONCOMPLIANT
    }

    error InvalidInput(uint8 input);

    function onConfidentialTransferReceived(
        address,
        address,
        euint64 amount,
        bytes calldata data
    ) external returns (ebool) {
        (Action action, address target) = abi.decode(data, (Action, address));

        if (action == Action.BLOCK_SELF) {
            IERC7984RestrictedMock(msg.sender).$_blockUser(address(this));
        } else if (action == Action.FREEZE_SELF) {
            IERC7984FreezableMock(msg.sender).$_setConfidentialFrozen(
                address(this),
                externalEuint64.wrap(euint64.unwrap(amount)),
                hex""
            );
        } else if (action == Action.SET_MODULE_NONCOMPLIANT) {
            ERC7984HookModuleMock(target).setIsCompliant(false);
        } else {
            revert InvalidInput(uint8(action));
        }

        ebool returnVal = FHE.asEbool(false);
        FHE.allowTransient(returnVal, msg.sender);

        return returnVal;
    }
}

interface IERC7984RestrictedMock {
    // solhint-disable-next-line func-name-mixedcase
    function $_blockUser(address account) external;
}

interface IERC7984FreezableMock {
    // solhint-disable-next-line func-name-mixedcase
    function $_setConfidentialFrozen(
        address account,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external;
}
