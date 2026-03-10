// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984} from "./IERC7984.sol";

/// @dev Interface for ERC7984ERC20Wrapper contract.
interface IERC7984ERC20Wrapper is IERC7984 {
    /**
     * @dev Wraps `amount` of the underlying token into a confidential token and sends it to `to`.
     *
     * Returns amount of wrapped token sent.
     */
    function wrap(address to, uint256 amount) external returns (euint64);

    /**
     * @dev Unwraps tokens from `from` and sends the underlying tokens to `to`. The caller must be `from`
     * or be an approved operator for `from`.
     *
     * Returns the unwrap request id.
     */
    function unwrap(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external returns (bytes32);

    /// @dev Returns the address of the underlying ERC-20 token that is being wrapped.
    function underlying() external view returns (address);

    /// @dev Finalizes an unwrap request identified by `unwrapRequestId`.
    function finalizeUnwrap(
        bytes32 unwrapRequestId,
        uint64 unwrapAmountCleartext,
        bytes calldata decryptionProof
    ) external;

    /**
     * @dev Returns the rate at which the underlying token is converted to the wrapped token.
     * For example, if the `rate` is 1000, then 1000 units of the underlying token equal 1 unit of the wrapped token.
     */
    function rate() external view returns (uint256);
}
