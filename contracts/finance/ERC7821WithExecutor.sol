// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC7821} from "@openzeppelin/contracts/account/extensions/draft-ERC7821.sol";

/**
 * @dev Extension of `ERC7821` that adds an {executor} address that is able to execute arbitrary calls via `ERC7821.execute`.
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

    /// @dev Trusted address that is able to execute arbitrary calls from the vesting wallet via `ERC7821.execute`.
    function executor() public view virtual returns (address) {
        return _getERC7821WithExecutorStorage()._executor;
    }

    // solhint-disable-next-line func-name-mixedcase
    function __ERC7821WithExecutor_init(address executor_) internal onlyInitializing {
        _getERC7821WithExecutorStorage()._executor = executor_;
    }

    /// @inheritdoc ERC7821
    function _erc7821AuthorizedExecutor(
        address caller,
        bytes32 mode,
        bytes calldata executionData
    ) internal view virtual override returns (bool) {
        return caller == executor() || super._erc7821AuthorizedExecutor(caller, mode, executionData);
    }

    function _getERC7821WithExecutorStorage() private pure returns (ERC7821WithExecutorStorage storage $) {
        assembly ("memory-safe") {
            $.slot := ERC7821WithExecutorStorageLocation
        }
    }
}
