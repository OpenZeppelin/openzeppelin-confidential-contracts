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

/**
 * @dev Extension of {ERC7984} supporting confidential Real World Assets.
 */
abstract contract ERC7984Rwa is ERC7984, ERC7984Freezable, Pausable, Multicall, ERC165, AccessControl {
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    /// @dev The caller account is not authorized to perform the operation.
    error UnauthorizedSender(address account);
    /// @dev The transfer does not follow token compliance.
    error UncompliantTransfer(address from, address to, euint64 encryptedAmount);

    constructor(string memory name, string memory symbol, string memory tokenUri) ERC7984(name, symbol, tokenUri) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// @dev Checks if the sender is an admin.
    modifier onlyAdmin() {
        require(isAdmin(_msgSender()), UnauthorizedSender(_msgSender()));
        _;
    }

    /// @dev Checks if the sender is an agent.
    modifier onlyAgent() {
        require(isAgent(_msgSender()), UnauthorizedSender(_msgSender()));
        _;
    }

    /// @dev Checks if the sender is an admin or an agent.
    modifier onlyAdminOrAgent() {
        require(isAdmin(_msgSender()) || isAgent(_msgSender()), UnauthorizedSender(_msgSender()));
        _;
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
    function addAgent(address account) public virtual {
        _addAgent(account);
    }

    /// @dev Removes agent.
    function removeAgent(address account) public virtual {
        _removeAgent(account);
    }

    /// @dev Mints confidential amount of tokens to account with proof.
    function confidentialMint(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64) {
        return _confidentialMint(to, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Mints confidential amount of tokens to account.
    function confidentialMint(address to, euint64 encryptedAmount) public virtual returns (euint64) {
        return _confidentialMint(to, encryptedAmount);
    }

    /// @dev Burns confidential amount of tokens from account with proof.
    function confidentialBurn(
        address account,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64) {
        return _confidentialBurn(account, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Burns confidential amount of tokens from account.
    function confidentialBurn(address account, euint64 encryptedAmount) public virtual returns (euint64) {
        return _confidentialBurn(account, encryptedAmount);
    }

    /// @dev Forces transfer of confidential amount of tokens from account to account with proof by skipping compliance checks.
    function forceConfidentialTransferFrom(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64) {
        return _forceConfidentialTransferFrom(from, to, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Forces transfer of confidential amount of tokens from account to account by skipping compliance checks.
    function forceConfidentialTransferFrom(
        address from,
        address to,
        euint64 encryptedAmount
    ) public virtual returns (euint64 transferred) {
        return _forceConfidentialTransferFrom(from, to, encryptedAmount);
    }

    /// @dev Internal function which adds an agent.
    function _addAgent(address account) internal virtual onlyAdminOrAgent {
        _grantRole(AGENT_ROLE, account);
    }

    /// @dev Internal function which removes an agent.
    function _removeAgent(address account) internal virtual onlyAdminOrAgent {
        _revokeRole(AGENT_ROLE, account);
    }

    /// @dev Internal function which mints confidential amount of tokens to account.
    function _confidentialMint(
        address to,
        euint64 encryptedAmount
    ) internal virtual onlyAdminOrAgent returns (euint64) {
        return _mint(to, encryptedAmount);
    }

    /// @dev Internal function which burns confidential amount of tokens from account.
    function _confidentialBurn(
        address account,
        euint64 encryptedAmount
    ) internal virtual onlyAdminOrAgent returns (euint64) {
        return _burn(account, encryptedAmount);
    }

    /// @dev Internal function which forces transfer of confidential amount of tokens from account to account by skipping compliance checks.
    function _forceConfidentialTransferFrom(
        address from,
        address to,
        euint64 encryptedAmount
    ) internal virtual onlyAdminOrAgent returns (euint64 transferred) {
        euint64 available = confidentialAvailable(from);
        transferred = ERC7984._update(from, to, encryptedAmount); // bypass frozen & compliance checks
        _setConfidentialFrozen(
            from,
            FHE.select(FHE.gt(transferred, available), confidentialBalanceOf(from), confidentialFrozen(from))
        );
    }

    /// @dev Internal function which updates confidential balances while performing frozen and compliance checks.
    function _update(
        address from,
        address to,
        euint64 encryptedAmount
    ) internal override(ERC7984, ERC7984Freezable) whenNotPaused returns (euint64) {
        require(_isCompliantTransfer(from, to, encryptedAmount), UncompliantTransfer(from, to, encryptedAmount));
        // frozen check performed through inheritance
        return super._update(from, to, encryptedAmount);
    }

    /**
     * @dev Internal function which reverts if `msg.sender` is not authorized as a freezer.
     * This freezer role is only granted to admin or agent.
     */
    function _checkFreezer() internal override onlyAdminOrAgent {}

    /// @dev Checks if a transfer follows token compliance.
    function _isCompliantTransfer(address from, address to, euint64 encryptedAmount) internal virtual returns (bool);
}
