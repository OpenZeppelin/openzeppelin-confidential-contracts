// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {FHE, externalEuint64, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC7984} from "./../interfaces/IERC7984.sol";
import {FHESafeMath} from "./../utils/FHESafeMath.sol";

contract ConfidentialAllowances {
    mapping(IERC7984 token => mapping(address owner => mapping(address spender => euint64))) private _allowances;

    function allowance(IERC7984 token, address owner, address spender) public view virtual returns (euint64) {
        return _allowances[token][owner][spender];
    }

    function setAllowance(IERC7984 token, address spender, uint256 amount) public virtual {
        _setAllowance(token, msg.sender, spender, FHE.asEuint64(SafeCast.toUint64(amount)));
    }

    function setAllowance(
        IERC7984 token,
        address spender,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual {
        _setAllowance(token, msg.sender, spender, FHE.fromExternal(encryptedAmount, inputProof));
    }

    function _setAllowance(IERC7984 token, address owner, address spender, euint64 amount) internal virtual {
        FHE.allowThis(amount);
        FHE.allow(amount, owner);
        FHE.allow(amount, spender);
        _allowances[token][owner][spender] = amount;
        // TODO: event ?
    }

    function confidentialTransferWithAllowance(
        IERC7984 token,
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64) {
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);

        // check if amount is within the bounds of allowance
        euint64 currentAllowance = allowance(token, from, msg.sender);

        // compute amount to try to transfer, and perform transfer
        euint64 transferred = token.confidentialTransfer(
            to,
            FHE.select(FHE.ge(currentAllowance, amount), amount, FHE.asEuint64(0))
        );
        // update (decrease) allowance.
        _setAllowance(token, from, msg.sender, FHE.sub(currentAllowance, transferred));

        FHE.allowTransient(transferred, msg.sender);
        return transferred;
    }

    function confidentialTransferAndCallWithAllowance(
        IERC7984 token,
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) public virtual returns (euint64) {
        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);

        // check if amount is within the bounds of allowance
        euint64 currentAllowance = allowance(token, from, msg.sender);

        // compute amount to try to transfer, and perform transfer
        euint64 transferred = token.confidentialTransferAndCall(
            to,
            FHE.select(FHE.ge(currentAllowance, amount), amount, FHE.asEuint64(0)),
            data
        );
        // update (decrease) allowance.
        _setAllowance(token, from, msg.sender, FHE.sub(currentAllowance, transferred));

        FHE.allowTransient(transferred, msg.sender);
        return transferred;
    }
}
