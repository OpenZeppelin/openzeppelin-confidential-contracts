// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {eaddress, euint64, externalEaddress, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";

/// @dev Library of helpers for working with ciphertext handles.
library HandleHelper {
    /**
     * @dev Converts the handle `encryptedAmount` to an `externalEuint64`. Useful for passing an existing handle to
     * functions that take an external encrypted amount, such as {IERC7984-confidentialTransfer}, along with an empty
     * input proof.
     */
    function toExternal(euint64 encryptedAmount) internal pure returns (externalEuint64) {
        return externalEuint64.wrap(euint64.unwrap(encryptedAmount));
    }

    /**
     * @dev Converts the handle `encryptedAddress` to an `externalEaddress`. Useful for passing an existing handle to
     * functions that take an external encrypted address, such as {ERC7984Omnibus-confidentialTransferOmnibus}, along
     * with an empty input proof.
     */
    function toExternal(eaddress encryptedAddress) internal pure returns (externalEaddress) {
        return externalEaddress.wrap(eaddress.unwrap(encryptedAddress));
    }
}
