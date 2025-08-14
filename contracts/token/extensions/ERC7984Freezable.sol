// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {euint64, externalEuint64} from "@fhevm/solidity/lib/FHE.sol";

abstract contract ERC7984Freezable {
    function confidentialFrozen(address account) public view virtual returns (euint64);
    function confidentialAvailable(address account) public virtual returns (euint64);
    function setConfidentialFrozen(
        address account,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual;
    function setConfidentialFrozen(address account, euint64 encryptedAmount) public virtual;
    function _checkFreezer() internal virtual;
}
