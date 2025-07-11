// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC7821} from "@openzeppelin/contracts/account/extensions/draft-ERC7821.sol";
import {VestingWalletConfidential} from "./VestingWalletConfidential.sol";

/**
 * @dev Extension of {VestingWalletConfidential} that adds an {executor} role able to perform arbitrary
 * calls on behalf of the vesting wallet (e.g. to vote, stake, or perform other management operations).
 */
//TODO: Rename file/name to WithExecutor
abstract contract VestingWalletExecutorConfidential is VestingWalletConfidential, ERC7821 {
    /// @custom:storage-location erc7201:openzeppelin.storage.VestingWalletExecutorConfidential
    struct VestingWalletExecutorStorage {
        address _executor;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.VestingWalletExecutorConfidential")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line const-name-snakecase
    bytes32 private constant VestingWalletExecutorStorageLocation =
        0x165c39f99e134d4ac22afe0db4de9fbb73791548e71f117f46b120e313690700;

    function _getVestingWalletExecutorStorage() private pure returns (VestingWalletExecutorStorage storage $) {
        assembly {
            $.slot := VestingWalletExecutorStorageLocation
        }
    }

    // solhint-disable-next-line func-name-mixedcase
    function __VestingWalletExecutorConfidential_init(address executor_) internal {
        _getVestingWalletExecutorStorage()._executor = executor_;
    }

    /// @dev Trusted address that is able to execute arbitrary calls from the vesting wallet via {call}.
    function executor() public view virtual returns (address) {
        return _getVestingWalletExecutorStorage()._executor;
    }

    function _erc7821AuthorizedExecutor(
        address caller,
        bytes32 mode,
        bytes calldata executionData
    ) internal view virtual override returns (bool) {
        return caller == executor() || super._erc7821AuthorizedExecutor(caller, mode, executionData);
    }
}
