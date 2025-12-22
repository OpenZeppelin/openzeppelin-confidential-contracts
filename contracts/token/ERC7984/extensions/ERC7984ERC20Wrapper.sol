// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.3.0) (token/ERC7984/extensions/ERC7984ERC20Wrapper.sol)

pragma solidity ^0.8.27;

import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC1363Receiver} from "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC7984} from "../../../interfaces/IERC7984.sol";
import {IERC7984ERC20Wrapper} from "../../../interfaces/IERC7984ERC20Wrapper.sol";
import {ERC7984} from "./../ERC7984.sol";

/**
 * @dev A wrapper contract built on top of {ERC7984} that allows wrapping an `ERC20` token
 * into an `ERC7984` token. The wrapper contract implements the `IERC1363Receiver` interface
 * which allows users to transfer `ERC1363` tokens directly to the wrapper with a callback to wrap the tokens.
 *
 * WARNING: Minting assumes the full amount of the underlying token transfer has been received, hence some non-standard
 * tokens such as fee-on-transfer or other deflationary-type tokens are not supported by this wrapper.
 */
abstract contract ERC7984ERC20Wrapper is ERC7984, IERC7984ERC20Wrapper {
    IERC20 private immutable _underlying;
    uint8 private immutable _decimals;
    uint256 private immutable _rate;

    mapping(euint64 unwrapAmount => address recipient) private _unwrapRequests;

    event UnwrapRequested(address indexed receiver, euint64 amount);
    event UnwrapFinalized(address indexed receiver, euint64 encryptedAmount, uint64 cleartextAmount);

    error InvalidUnwrapRequest(euint64 amount);
    error ERC7984TotalSupplyOverflow();

    constructor(IERC20 underlying_) {
        _underlying = underlying_;

        uint8 tokenDecimals = _tryGetAssetDecimals(underlying_);
        uint8 maxDecimals = _maxDecimals();
        if (tokenDecimals > maxDecimals) {
            _decimals = maxDecimals;
            _rate = 10 ** (tokenDecimals - maxDecimals);
        } else {
            _decimals = tokenDecimals;
            _rate = 1;
        }
    }

    /// @inheritdoc IERC7984ERC20Wrapper
    function onTransferReceived(
        address /*operator*/,
        address from,
        uint256 amount,
        bytes calldata data
    ) public virtual returns (bytes4) {
        // check caller is the token contract
        require(address(underlying()) == msg.sender, ERC7984UnauthorizedCaller(msg.sender));

        // mint confidential token
        address to = data.length < 20 ? from : address(bytes20(data));
        _mint(to, FHE.asEuint64(SafeCast.toUint64(amount / rate())));

        // transfer excess back to the sender
        uint256 excess = amount % rate();
        if (excess > 0) SafeERC20.safeTransfer(underlying(), from, excess);

        // return magic value
        return IERC1363Receiver.onTransferReceived.selector;
    }

    /// @inheritdoc IERC7984ERC20Wrapper
    function wrap(address to, uint256 amount) public virtual {
        // take ownership of the tokens
        SafeERC20.safeTransferFrom(underlying(), msg.sender, address(this), amount - (amount % rate()));

        // mint confidential token
        _mint(to, FHE.asEuint64(SafeCast.toUint64(amount / rate())));
    }

    /// @inheritdoc IERC7984ERC20Wrapper
    function unwrap(address from, address to, euint64 amount) public virtual {
        require(FHE.isAllowed(amount, msg.sender), ERC7984UnauthorizedUseOfEncryptedAmount(amount, msg.sender));
        _unwrap(from, to, amount);
    }

    /// @inheritdoc IERC7984ERC20Wrapper
    function unwrap(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual {
        _unwrap(from, to, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @inheritdoc IERC7984ERC20Wrapper
    function finalizeUnwrap(
        euint64 burntAmount,
        uint64 burntAmountCleartext,
        bytes calldata decryptionProof
    ) public virtual {
        address to = _unwrapRequests[burntAmount];
        require(to != address(0), InvalidUnwrapRequest(burntAmount));
        delete _unwrapRequests[burntAmount];

        bytes32[] memory handles = new bytes32[](1);
        handles[0] = euint64.unwrap(burntAmount);

        bytes memory cleartexts = abi.encode(burntAmountCleartext);

        FHE.checkSignatures(handles, cleartexts, decryptionProof);

        SafeERC20.safeTransfer(underlying(), to, burntAmountCleartext * rate());

        emit UnwrapFinalized(to, burntAmount, burntAmountCleartext);
    }

    /// @inheritdoc ERC7984
    function decimals() public view virtual override(IERC7984, ERC7984) returns (uint8) {
        return _decimals;
    }

    /// @inheritdoc IERC7984ERC20Wrapper
    function rate() public view virtual returns (uint256) {
        return _rate;
    }

    /// @inheritdoc IERC7984ERC20Wrapper
    function underlying() public view returns (IERC20) {
        return _underlying;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC7984) returns (bool) {
        return interfaceId == type(IERC7984ERC20Wrapper).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IERC7984ERC20Wrapper
    function totalSupply() public view virtual returns (uint256) {
        return underlying().balanceOf(address(this)) / rate();
    }

    /// @inheritdoc IERC7984ERC20Wrapper
    function maxTotalSupply() public view virtual returns (uint256) {
        return type(uint64).max;
    }

    /**
     * @dev This function must revert if the new {confidentialTotalSupply} is invalid (overflow occurred).
     *
     * NOTE: Overflow can be detected here since the wrapper holdings are non-confidential. In other cases, it may be impossible
     * to infer total supply overflow synchronously. This function may revert even if the {confidentialTotalSupply} did
     * not overflow.
     */
    function _checkConfidentialTotalSupply() internal virtual {
        if (totalSupply() > maxTotalSupply()) {
            revert ERC7984TotalSupplyOverflow();
        }
    }

    function _update(address from, address to, euint64 amount) internal virtual override returns (euint64) {
        if (from == address(0)) {
            _checkConfidentialTotalSupply();
        }
        return super._update(from, to, amount);
    }

    function _unwrap(address from, address to, euint64 amount) internal virtual {
        require(to != address(0), ERC7984InvalidReceiver(to));
        require(from == msg.sender || isOperator(from, msg.sender), ERC7984UnauthorizedSpender(from, msg.sender));

        // try to burn, see how much we actually got
        euint64 burntAmount = _burn(from, amount);
        FHE.makePubliclyDecryptable(burntAmount);

        assert(_unwrapRequests[burntAmount] == address(0));
        _unwrapRequests[burntAmount] = to;

        emit UnwrapRequested(to, burntAmount);
    }

    /**
     * @dev Returns the default number of decimals of the underlying ERC-20 token that is being wrapped.
     * Used as a default fallback when {_tryGetAssetDecimals} fails to fetch decimals of the underlying
     * ERC-20 token.
     */
    function _fallbackUnderlyingDecimals() internal pure virtual returns (uint8) {
        return 18;
    }

    /**
     * @dev Returns the maximum number that will be used for {decimals} by the wrapper.
     */
    function _maxDecimals() internal pure virtual returns (uint8) {
        return 6;
    }

    function _tryGetAssetDecimals(IERC20 asset_) private view returns (uint8 assetDecimals) {
        (bool success, bytes memory encodedDecimals) = address(asset_).staticcall(
            abi.encodeCall(IERC20Metadata.decimals, ())
        );
        if (success && encodedDecimals.length == 32) {
            return abi.decode(encodedDecimals, (uint8));
        }
        return _fallbackUnderlyingDecimals();
    }
}
