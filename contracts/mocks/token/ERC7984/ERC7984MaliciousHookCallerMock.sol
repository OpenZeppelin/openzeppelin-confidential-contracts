// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984HookModule} from "../../../interfaces/IERC7984HookModule.sol";
import {HandleAccessManager} from "../../../utils/HandleAccessManager.sol";

/// @dev A token mock that returns balance handles it has no FHE allowance for, and whose
/// {HandleAccessManager-getHandleAllowance} silently succeeds without granting any access.
///
/// Attack flow when used as the token caller of a hook module:
/// 1. {callPreTransfer} / {callPostTransfer} create an `encryptedAmount` this contract owns,
///    satisfying the hook module's `FHE.isAllowed(encryptedAmount, msg.sender)` guard.
/// 2. Inside the hook module, `token.confidentialBalanceOf(account)` returns a handle stored
///    via {setConfidentialBalance} — a handle this contract was never allowed to use.
/// 3. `token.getHandleAllowance(handle, hookModule, false)` returns silently without granting access.
/// 4. The hook module must check that the caller has allowance to the balance handles it returns.
contract ERC7984MaliciousHookCallerMock is HandleAccessManager, ZamaEthereumConfig {
    mapping(address => euint64) private _balances;

    function confidentialBalanceOf(address account) external view returns (euint64) {
        return _balances[account];
    }

    /// @dev Stores `balance` for `account` without granting FHE allowance to this contract,
    /// so {confidentialBalanceOf} returns a handle this contract cannot use.
    function setConfidentialBalance(address account, euint64 balance) external {
        _balances[account] = balance;
    }

    /// @dev Creates an encrypted balance owned by this contract (FHE.allowThis is called),
    /// so {confidentialBalanceOf} returns a handle this contract is allowed to use.
    function setConfidentialBalanceWithAllowance(address account, uint64 amount) external {
        euint64 balance = FHE.asEuint64(amount);
        FHE.allowThis(balance);
        _balances[account] = balance;
    }

    /// @dev Calls `hookModule.preTransfer` with this contract as the token (msg.sender).
    /// Creates an `encryptedAmount` owned by this contract so the hook module's entry-point
    /// allowance check passes before the unallowed balance handles are encountered.
    function callPreTransfer(address hookModule, address from, address to, uint64 amount) external {
        euint64 encryptedAmount = FHE.asEuint64(amount);
        FHE.allowThis(encryptedAmount);
        FHE.allowTransient(encryptedAmount, hookModule);
        IERC7984HookModule(hookModule).preTransfer(from, to, encryptedAmount);
    }

    /// @dev Calls `hookModule.postTransfer` with this contract as the token (msg.sender).
    function callPostTransfer(address hookModule, address from, address to, uint64 amount) external {
        euint64 encryptedAmount = FHE.asEuint64(amount);
        FHE.allowThis(encryptedAmount);
        FHE.allowTransient(encryptedAmount, hookModule);
        IERC7984HookModule(hookModule).postTransfer(from, to, encryptedAmount);
    }

    /// @dev Silently returns without reverting and without granting any handle allowance.
    function getHandleAllowance(bytes32 /*handle*/, address /*account*/, bool /*persistent*/) public override {
        // Intentionally a no-op: does not revert and does not grant access
    }

    /// @dev Always returns false — this contract never validates handle ownership.
    function _validateHandleAllowance(bytes32 /*handle*/) internal pure override returns (bool) {
        return false;
    }
}
