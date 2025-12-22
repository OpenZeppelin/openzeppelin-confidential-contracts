// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC1363Receiver} from "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";
import {IERC7984} from "./IERC7984.sol";

/// @dev Interface for ERC7984ERC20Wrapper contract.
interface IERC7984ERC20Wrapper is IERC7984, IERC1363Receiver {
    /**
     * @dev Wraps amount `amount` of the underlying token into a confidential token and sends it to
     * `to`. Tokens are exchanged at a fixed rate specified by {rate} such that `amount / rate()` confidential
     * tokens are sent. Amount transferred in is rounded down to the nearest multiple of {rate}.
     */
    function wrap(address to, uint256 amount) external;
    /**
     * @dev Unwraps tokens from `from` and sends the underlying tokens to `to`. The caller must be `from`
     * or be an approved operator for `from`. `amount * rate()` underlying tokens are sent to `to`.
     *
     * NOTE: The unwrap request created by this function must be finalized by calling {finalizeUnwrap}.
     * NOTE: The caller *must* already be approved by ACL for the given `amount`.
     */
    function unwrap(address from, address to, euint64 amount) external;
    /**
     * @dev Variant of {unwrap} that passes an `inputProof` which approves the caller for the `encryptedAmount`
     * in the ACL.
     */
    function unwrap(address from, address to, externalEuint64 encryptedAmount, bytes calldata inputProof) external;
    /// @dev Fills an unwrap request for a given cipher-text `burntAmount` with the `cleartextAmount` and `decryptionProof`.
    function finalizeUnwrap(euint64 burntAmount, uint64 burntAmountCleartext, bytes calldata decryptionProof) external;
    /**
     * @dev Returns the rate at which the underlying token is converted to the wrapped token.
     * For example, if the `rate` is 1000, then 1000 units of the underlying token equal 1 unit of the wrapped token.
     */
    function rate() external view returns (uint256);
    /// @dev Returns the address of the underlying ERC-20 token that is being wrapped.
    function underlying() external view returns (IERC20);
    /**
     * @dev Returns the underlying balance divided by the {rate}, a value greater or equal to the actual
     * {confidentialTotalSupply}.
     *
     * NOTE: The return value of this function can be inflated by directly sending underlying tokens to the wrapper contract.
     * Reductions will lag compared to {confidentialTotalSupply} since it is updated on {unwrap} while this function updates
     * on {finalizeUnwrap}.
     */
    function totalSupply() external view returns (uint256);
    /// @dev Returns the maximum total supply of wrapped tokens supported by the encrypted datatype.
    function maxTotalSupply() external view returns (uint256);
}
