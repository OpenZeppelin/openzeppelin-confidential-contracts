// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC7821} from "@openzeppelin/contracts/account/extensions/draft-ERC7821.sol";

/**
 * @dev Extension of {VestingWalletConfidential} that adds an {executor} role able to perform arbitrary
 * calls on behalf of the vesting wallet (e.g. to vote, stake, or perform other management operations).
 */
abstract contract ERC7821WithExecutor is Initializable, ERC7821 {
    /// @custom:storage-location erc7201:openzeppelin.storage.ERC7821WithExecutor
    struct ERC7821WithExecutorStorage {
        address _executor;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC7821WithExecutor")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line const-name-snakecase
    bytes32 private constant ERC7821WithExecutorStorageLocation =
        0x246106ffca67a7d3806ba14f6748826b9c39c9fa594b14f83fe454e8e9d0dc00;

    function _getERC7821WithExecutorStorage() private pure returns (ERC7821WithExecutorStorage storage $) {
        assembly {
            $.slot := ERC7821WithExecutorStorageLocation
        }
    }

    // solhint-disable-next-line func-name-mixedcase
    function __ERC7821WithExecutor_init(address executor_) internal onlyInitializing {
        _getERC7821WithExecutorStorage()._executor = executor_;
    }

    /// @dev Trusted address that is able to execute arbitrary calls from the vesting wallet via `ERC7821`.
    function executor() public view virtual returns (address) {
        return _getERC7821WithExecutorStorage()._executor;
    }

    function _erc7821AuthorizedExecutor(
        address caller,
        bytes32 mode,
        bytes calldata executionData
    ) internal view virtual override returns (bool) {
        return caller == executor() || super._erc7821AuthorizedExecutor(caller, mode, executionData);
    }
}
