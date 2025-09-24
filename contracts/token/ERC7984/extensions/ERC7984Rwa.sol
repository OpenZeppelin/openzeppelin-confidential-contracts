// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC7984} from "./../../../interfaces/IERC7984.sol";
import {IERC7984Rwa} from "./../../../interfaces/IERC7984Rwa.sol";
import {FHESafeMath} from "./../../../utils/FHESafeMath.sol";
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
    // bytes4(keccak256("forceConfidentialTransferFrom(address,address,bytes32)"))
    bytes4 private constant FORCE_CONFIDENTIAL_TRANSFER_FROM_SIG = 0x6c9c3c85;
    // bytes4(keccak256("forceConfidentialTransferFrom(address,address,bytes32,bytes)"))
    bytes4 private constant FORCE_CONFIDENTIAL_TRANSFER_FROM_WITH_PROOF_SIG = 0x44fd6e40;

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

    constructor(
        string memory name,
        string memory symbol,
        string memory tokenUri,
        address admin
    ) ERC7984(name, symbol, tokenUri) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, AccessControl) returns (bool) {
        return
            interfaceId == type(IERC7984Rwa).interfaceId ||
            interfaceId == type(IERC7984).interfaceId ||
            super.supportsInterface(interfaceId);
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

    /// @dev Pauses contract.
    function pause() public virtual onlyAgent {
        _pause();
    }

    /// @dev Unpauses contract.
    function unpause() public virtual onlyAgent {
        _unpause();
    }

    /// @dev Blocks a user account.
    function blockUser(address account) public virtual onlyAgent {
        _blockUser(account);
    }

    /// @dev Unblocks a user account.
    function unblockUser(address account) public virtual onlyAgent {
        _allowUser(account);
    }

    /// @dev Sets confidential frozen for an account.
    function setConfidentialFrozen(
        address account,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual onlyAgent {
        _setConfidentialFrozen(account, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Sets confidential frozen for an account with proof.
    function setConfidentialFrozen(address account, euint64 encryptedAmount) public virtual onlyAgent {
        require(
            FHE.isAllowed(encryptedAmount, msg.sender),
            ERC7984UnauthorizedUseOfEncryptedAmount(encryptedAmount, msg.sender)
        );
        _setConfidentialFrozen(account, encryptedAmount);
    }

    /// @dev Mints confidential amount of tokens to account with proof.
    function confidentialMint(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual onlyAgent returns (euint64) {
        return _mint(to, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Mints confidential amount of tokens to account.
    function confidentialMint(address to, euint64 encryptedAmount) public virtual onlyAgent returns (euint64) {
        require(
            FHE.isAllowed(encryptedAmount, msg.sender),
            ERC7984UnauthorizedUseOfEncryptedAmount(encryptedAmount, msg.sender)
        );
        return _mint(to, encryptedAmount);
    }

    /// @dev Burns confidential amount of tokens from account with proof.
    function confidentialBurn(
        address account,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual onlyAgent returns (euint64) {
        return _burn(account, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Burns confidential amount of tokens from account.
    function confidentialBurn(address account, euint64 encryptedAmount) public virtual onlyAgent returns (euint64) {
        require(
            FHE.isAllowed(encryptedAmount, msg.sender),
            ERC7984UnauthorizedUseOfEncryptedAmount(encryptedAmount, msg.sender)
        );
        return _burn(account, encryptedAmount);
    }

    /// @dev Forces transfer of confidential amount of tokens from account to account with proof by skipping compliance checks.
    function forceConfidentialTransferFrom(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual onlyAgent returns (euint64) {
        return _forceUpdate(from, to, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Forces transfer of confidential amount of tokens from account to account by skipping compliance checks.
    function forceConfidentialTransferFrom(
        address from,
        address to,
        euint64 encryptedAmount
    ) public virtual onlyAgent returns (euint64 transferred) {
        require(
            FHE.isAllowed(encryptedAmount, msg.sender),
            ERC7984UnauthorizedUseOfEncryptedAmount(encryptedAmount, msg.sender)
        );
        return _forceUpdate(from, to, encryptedAmount);
    }

    /// @dev Internal function which updates confidential balances while performing frozen and restriction compliance checks.
    function _update(
        address from,
        address to,
        euint64 encryptedAmount
    ) internal override(ERC7984Freezable, ERC7984Restricted, ERC7984) whenNotPaused returns (euint64) {
        // frozen and restriction checks performed through inheritance
        return super._update(from, to, encryptedAmount);
    }

    /// @dev Internal function which forces transfer of confidential amount of tokens from account to account by skipping compliance checks.
    function _forceUpdate(address from, address to, euint64 encryptedAmount) internal virtual returns (euint64) {
        euint64 senderFrozenAmount = confidentialFrozen(from);
        if (FHE.isInitialized(senderFrozenAmount)) {
            (, euint64 newFrozen) = FHESafeMath.tryDecrease(senderFrozenAmount, encryptedAmount);
            _setConfidentialFrozen(from, newFrozen);
        }

        // bypassing `from` restriction check with {_checkSenderRestriction}
        // bypassing `from` frozen check with {confidentialAvailable}
        return super._update(from, to, encryptedAmount); // still performing `to` restriction check
    }

    /**
     * @dev Bypasses the `from` restriction check when performing a {forceConfidentialTransferFrom}.
     */
    function _checkSenderRestriction(address account) internal view override {
        if (_isForceTransfer()) {
            return;
        }
        super._checkSenderRestriction(account);
    }

    function confidentialAvailable(address account) public virtual override returns (euint64) {
        if (_isForceTransfer()) {
            return confidentialBalanceOf(account);
        } else {
            return super.confidentialAvailable(account);
        }
    }

    /// @dev Private function which checks if the called function is a {forceConfidentialTransferFrom}.
    function _isForceTransfer() private pure returns (bool) {
        return
            msg.sig == FORCE_CONFIDENTIAL_TRANSFER_FROM_SIG ||
            msg.sig == FORCE_CONFIDENTIAL_TRANSFER_FROM_WITH_PROOF_SIG;
    }
}
