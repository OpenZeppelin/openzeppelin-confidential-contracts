// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC7984} from "./../../../interfaces/IERC7984.sol";
import {IERC7984RwaBase} from "./../../../interfaces/IERC7984Rwa.sol";
import {ERC7984} from "./../ERC7984.sol";
import {ERC7984Freezable} from "./ERC7984Freezable.sol";
import {ERC7984Restricted} from "./ERC7984Restricted.sol";

/**
 * @dev Extension of {ERC7984} that supports confidential Real World Assets (RWAs).
 * This interface provides compliance checks, transfer controls and enforcement actions.
 */
abstract contract ERC7984Rwa is
    ERC7984,
    ERC7984Freezable,
    ERC7984Restricted,
    Pausable,
    Multicall,
    ERC165,
    AccessControl
{
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    /// @dev The caller account is not authorized to perform the operation.
    error UnauthorizedSender(address account);
    /// @dev The transfer does not follow token compliance.
    error UncompliantTransfer(address from, address to, euint64 encryptedAmount);

    /// @dev Checks if the sender is an admin or an agent.
    modifier onlyAdminOrAgent() {
        require(isAdmin(_msgSender()) || isAgent(_msgSender()), UnauthorizedSender(_msgSender()));
        _;
    }

    constructor(string memory name, string memory symbol, string memory tokenUri) ERC7984(name, symbol, tokenUri) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, AccessControl) returns (bool) {
        return
            interfaceId == type(IERC7984RwaBase).interfaceId ||
            interfaceId == type(IERC7984).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @dev Pauses contract.
    function pause() public virtual onlyAdminOrAgent {
        _pause();
    }

    /// @dev Unpauses contract.
    function unpause() public virtual onlyAdminOrAgent {
        _unpause();
    }

    /// @dev Returns true if has admin role, false otherwise.
    function isAdmin(address account) public view virtual returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account);
    }

    /// @dev Returns true if agent, false otherwise.
    function isAgent(address account) public view virtual returns (bool) {
        return hasRole(AGENT_ROLE, account);
    }

    /// @dev Adds agent.
    function addAgent(address account) public virtual onlyAdminOrAgent {
        _addAgent(account);
    }

    /// @dev Removes agent.
    function removeAgent(address account) public virtual onlyAdminOrAgent {
        _removeAgent(account);
    }

    /// @dev Blocks a user account.
    function blockUser(address account) public virtual onlyAdminOrAgent {
        _blockUser(account);
    }

    /// @dev Unblocks a user account.
    function unblockUser(address account) public virtual onlyAdminOrAgent {
        _allowUser(account);
    }

    /// @dev Mints confidential amount of tokens to account with proof.
    function confidentialMint(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual onlyAdminOrAgent returns (euint64) {
        return _confidentialMint(to, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Mints confidential amount of tokens to account.
    function confidentialMint(address to, euint64 encryptedAmount) public virtual onlyAdminOrAgent returns (euint64) {
        return _confidentialMint(to, encryptedAmount);
    }

    /// @dev Burns confidential amount of tokens from account with proof.
    function confidentialBurn(
        address account,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual onlyAdminOrAgent returns (euint64) {
        return _confidentialBurn(account, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Burns confidential amount of tokens from account.
    function confidentialBurn(
        address account,
        euint64 encryptedAmount
    ) public virtual onlyAdminOrAgent returns (euint64) {
        return _confidentialBurn(account, encryptedAmount);
    }

    /// @dev Forces transfer of confidential amount of tokens from account to account with proof by skipping compliance checks.
    function forceConfidentialTransferFrom(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual onlyAdminOrAgent returns (euint64) {
        return _forceConfidentialTransferFrom(from, to, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Forces transfer of confidential amount of tokens from account to account by skipping compliance checks.
    function forceConfidentialTransferFrom(
        address from,
        address to,
        euint64 encryptedAmount
    ) public virtual onlyAdminOrAgent returns (euint64 transferred) {
        return _forceConfidentialTransferFrom(from, to, encryptedAmount);
    }

    /// @dev Internal function which adds an agent.
    function _addAgent(address account) internal virtual {
        _grantRole(AGENT_ROLE, account);
    }

    /// @dev Internal function which removes an agent.
    function _removeAgent(address account) internal virtual {
        _revokeRole(AGENT_ROLE, account);
    }

    /// @dev Internal function which mints confidential amount of tokens to account.
    function _confidentialMint(address to, euint64 encryptedAmount) internal virtual returns (euint64) {
        return _mint(to, encryptedAmount);
    }

    /// @dev Internal function which burns confidential amount of tokens from account.
    function _confidentialBurn(address account, euint64 encryptedAmount) internal virtual returns (euint64) {
        return _burn(account, encryptedAmount);
    }

    /// @dev Internal function which forces transfer of confidential amount of tokens from account to account by skipping compliance checks.
    function _forceConfidentialTransferFrom(
        address from,
        address to,
        euint64 encryptedAmount
    ) internal virtual returns (euint64 transferred) {
        require(_isForceTransferCompliant(from, to, encryptedAmount), UncompliantTransfer(from, to, encryptedAmount));
        _disableERC7984FreezableUpdateCheck(); // bypass frozen check
        _disableERC7984RestrictedUpdateCheck(); // bypass default restriction check
        if (to != address(0)) _checkRestriction(to); // only perform restriction check on `to`
        transferred = super._update(from, to, encryptedAmount); // bypass compliance check
        _postForceTransferHook(from, to, encryptedAmount);
        _restoreERC7984FreezableUpdateCheck();
        _restoreERC7984RestrictedUpdateCheck();
    }

    /// @dev Internal function which updates confidential balances while performing frozen, restriction and compliance checks.
    function _update(
        address from,
        address to,
        euint64 encryptedAmount
    ) internal override(ERC7984Freezable, ERC7984Restricted, ERC7984) whenNotPaused returns (euint64 transferred) {
        require(_isTransferCompliant(from, to, encryptedAmount), UncompliantTransfer(from, to, encryptedAmount));
        // frozen and restriction checks performed through inheritance
        transferred = super._update(from, to, encryptedAmount);
        _postTransferHook(from, to, encryptedAmount);
    }

    /**
     * @dev Internal function which reverts if `msg.sender` is not authorized as a freezer.
     * This freezer role is only granted to admin or agent.
     */
    function _checkFreezer() internal override onlyAdminOrAgent {}

    /// @dev Checks if a transfer follows compliance.
    function _isTransferCompliant(address from, address to, euint64 encryptedAmount) internal virtual returns (bool);

    /// @dev Checks if a force transfer follows compliance.
    function _isForceTransferCompliant(
        address from,
        address to,
        euint64 encryptedAmount
    ) internal virtual returns (bool);

    /// @dev Performs operation after transfer.
    function _postTransferHook(address from, address to, euint64 encryptedAmount) internal virtual {}

    /// @dev Performs operation after force transfer.
    function _postForceTransferHook(address from, address to, euint64 encryptedAmount) internal virtual {}
}
