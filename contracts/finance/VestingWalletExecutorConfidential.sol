// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {VestingWalletConfidential} from "./VestingWalletConfidential.sol";

/**
 * @dev Extension of {VestingWalletConfidential} that adds an {executor} role able to perform arbitrary
 * calls on behalf of the vesting wallet (e.g. to vote, stake, or perform other management operations).
 */
abstract contract VestingWalletExecutorConfidential is VestingWalletConfidential {
    /// @custom:storage-location erc7201:openzeppelin.storage.VestingWalletExecutorConfidential
    struct VestingWalletExecutorStorage {
        address _executor;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.VestingWalletExecutorConfidential")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VestingWalletExecutorStorageLocation =
        0x165c39f99e134d4ac22afe0db4de9fbb73791548e71f117f46b120e313690700;

    function _getVestingWalletExecutorStorage() private pure returns (VestingWalletExecutorStorage storage $) {
        assembly {
            $.slot := VestingWalletExecutorStorageLocation
        }
    }

    event VestingWalletExecutorConfidentialCallExecuted(address indexed target, uint256 value, bytes data);

    /// @dev Revert thrown when a non-executor attempts to call {call}.
    error VestingWalletExecutorConfidentialOnlyExecutor();

    // solhint-disable-next-line func-name-mixedcase
    function __VestingWalletExecutorConfidential_init(address executor_) internal onlyInitializing {
        VestingWalletExecutorStorage storage $ = _getVestingWalletExecutorStorage();
        $._executor = executor_;
    }

    /// @dev Address that is able to execute arbitrary calls from the vesting wallet via {call}.
    function executor() public view virtual returns (address) {
        return _getVestingWalletExecutorStorage()._executor;
    }

    /**
     * @dev Execute an arbitrary call from the vesting wallet. Only callable by the {executor}.
     *
     * Emits a {VestingWalletExecutorConfidentialCallExecuted} event.
     */
    function call(address target, uint256 value, bytes memory data) public virtual {
        require(msg.sender == executor(), VestingWalletExecutorConfidentialOnlyExecutor());
        _call(target, value, data);
    }

    /// @dev Internal execution of an arbitrary call from the vesting wallet.
    function _call(address target, uint256 value, bytes memory data) internal virtual {
        (bool success, bytes memory res) = target.call{value: value}(data);
        Address.verifyCallResult(success, res);

        emit VestingWalletExecutorConfidentialCallExecuted(target, value, data);
    }
}
