// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC7984} from "./../../../interfaces/IERC7984.sol";
import {IERC7984Rwa} from "./../../../interfaces/IERC7984Rwa.sol";
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

    /// @dev The transfer does not follow token compliance.
    error UncompliantTransfer(address from, address to, euint64 encryptedAmount);

    /// @dev Checks if the sender is an admin.
    modifier onlyAdmin() {
        _checkRole(DEFAULT_ADMIN_ROLE);
        _;
    }

    /// @dev Checks if the sender is an agent.
    modifier onlyAgent() {
        _checkRole(AGENT_ROLE);
        _;
    }

    constructor(string memory name, string memory symbol, string memory tokenUri) ERC7984(name, symbol, tokenUri) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, AccessControl) returns (bool) {
        return
            interfaceId == type(IERC7984Rwa).interfaceId ||
            interfaceId == type(IERC7984).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @dev Pauses contract.
    function pause() public virtual onlyAgent {
        _pause();
    }

    /// @dev Unpauses contract.
    function unpause() public virtual onlyAgent {
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
    function addAgent(address account) public virtual onlyAdmin {
        _grantRole(AGENT_ROLE, account);
    }

    /// @dev Removes agent.
    function removeAgent(address account) public virtual onlyAdmin {
        _revokeRole(AGENT_ROLE, account);
    }

    /// @dev Blocks a user account.
    function blockUser(address account) public virtual onlyAgent {
        _blockUser(account);
    }

    /// @dev Unblocks a user account.
    function unblockUser(address account) public virtual onlyAgent {
        _allowUser(account);
    }

    /// @dev Sets confidential frozen with proof.
    function setConfidentialFrozen(address account, euint64 encryptedAmount) public virtual onlyAgent {
        require(
            FHE.isAllowed(encryptedAmount, account),
            ERC7984UnauthorizedUseOfEncryptedAmount(encryptedAmount, msg.sender)
        );
        _setConfidentialFrozen(account, encryptedAmount);
    }

    /// @dev Sets confidential frozen.
    function setConfidentialFrozen(
        address account,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual onlyAgent {
        _setConfidentialFrozen(account, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Mints confidential amount of tokens to account with proof.
    function confidentialMint(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual onlyAgent returns (euint64) {
        return _confidentialMint(to, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Mints confidential amount of tokens to account.
    function confidentialMint(address to, euint64 encryptedAmount) public virtual onlyAgent returns (euint64) {
        return _confidentialMint(to, encryptedAmount);
    }

    /// @dev Burns confidential amount of tokens from account with proof.
    function confidentialBurn(
        address account,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual onlyAgent returns (euint64) {
        return _confidentialBurn(account, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Burns confidential amount of tokens from account.
    function confidentialBurn(address account, euint64 encryptedAmount) public virtual onlyAgent returns (euint64) {
        return _confidentialBurn(account, encryptedAmount);
    }

    /// @dev Forces transfer of confidential amount of tokens from account to account with proof by skipping compliance checks.
    function forceConfidentialTransferFrom(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual onlyAgent returns (euint64) {
        return _forceConfidentialTransferFrom(from, to, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Forces transfer of confidential amount of tokens from account to account by skipping compliance checks.
    function forceConfidentialTransferFrom(
        address from,
        address to,
        euint64 encryptedAmount
    ) public virtual onlyAgent returns (euint64 transferred) {
        return _forceConfidentialTransferFrom(from, to, encryptedAmount);
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
        // bypassing `from` restriction & frozen checks while `to` restriction check is still performed.
        transferred = super._update(from, to, encryptedAmount); // bypass compliance check
    }

    /**
     * @dev Bypasses the `from` restriction check when performing a {forceConfidentialTransferFrom}.
     */
    function _checkRestrictionFrom(address account) internal view override {
        if (_isForceTransfer()) {
            return;
        }
        super._checkRestrictionFrom(account);
    }

    /**
     * @dev Bypasses the frozen check of the `from` account when performing a {forceConfidentialTransferFrom}.
     */
    function _getUnfrozenAvailableFrom(address account, euint64 encryptedAmount) internal override returns (euint64) {
        if (_isForceTransfer()) {
            return encryptedAmount;
        }
        return super._getUnfrozenAvailableFrom(account, encryptedAmount);
    }

    /// @dev Internal function which updates confidential balances while performing frozen, restriction and compliance checks.
    function _update(
        address from,
        address to,
        euint64 encryptedAmount
    ) internal override(ERC7984Freezable, ERC7984Restricted, ERC7984) whenNotPaused returns (euint64) {
        require(_isCompliantTransfer(from, to, encryptedAmount), UncompliantTransfer(from, to, encryptedAmount));
        // frozen and restriction checks performed through inheritance
        return super._update(from, to, encryptedAmount);
    }

    /**
     * @dev Internal function which reverts if `msg.sender` is not authorized as a freezer.
     * This freezer role is only granted to admin or agent.
     */
    function _checkFreezer() internal override onlyAgent {}

    /// @dev Checks if a transfer follows token compliance.
    function _isCompliantTransfer(address from, address to, euint64 encryptedAmount) internal virtual returns (bool);

    /// @dev Private function which checks if the called function is a {forceConfidentialTransferFrom}.
    function _isForceTransfer() private pure returns (bool) {
        return
            msg.sig == bytes4(keccak256("forceConfidentialTransferFrom(address,address,bytes32)")) ||
            msg.sig == bytes4(keccak256("forceConfidentialTransferFrom(address,address,bytes32,bytes)"));
    }
}
