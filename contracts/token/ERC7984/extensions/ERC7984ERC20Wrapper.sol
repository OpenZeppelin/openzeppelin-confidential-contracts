// SPDX-License-Identifier: MIT
// OpenZeppelin Confidential Contracts (last updated v0.3.1) (token/ERC7984/extensions/ERC7984ERC20Wrapper.sol)

pragma solidity ^0.8.27;

import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC1363Receiver} from "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC7984} from "./../ERC7984.sol";

/**
 * @dev A wrapper contract built on top of {ERC7984} that allows wrapping an `ERC20` token
 * into an `ERC7984` token. The wrapper contract implements the `IERC1363Receiver` interface
 * which allows users to transfer `ERC1363` tokens directly to the wrapper with a callback to wrap the tokens.
 *
 * WARNING: Minting assumes the full amount of the underlying token transfer has been received, hence some non-standard
 * tokens such as fee-on-transfer or other deflationary-type tokens are not supported by this wrapper.
 */
abstract contract ERC7984ERC20Wrapper is ERC7984, IERC1363Receiver {
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

    /**
     * @dev `ERC1363` callback function which wraps tokens to the address specified in `data` or
     * the address `from` (if no address is specified in `data`). This function refunds any excess tokens
     * sent beyond the nearest multiple of {rate} to `from`. See {wrap} from more details on wrapping tokens.
     */
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

    /**
     * @dev Wraps amount `amount` of the underlying token into a confidential token and sends it to
     * `to`. Tokens are exchanged at a fixed rate specified by {rate} such that `amount / rate()` confidential
     * tokens are sent. Amount transferred in is rounded down to the nearest multiple of {rate}.
     */
    function wrap(address to, uint256 amount) public virtual {
        // take ownership of the tokens
        SafeERC20.safeTransferFrom(underlying(), msg.sender, address(this), amount - (amount % rate()));

        // mint confidential token
        _mint(to, FHE.asEuint64(SafeCast.toUint64(amount / rate())));
    }

    /**
     * @dev Unwraps tokens from `from` and sends the underlying tokens to `to`. The caller must be `from`
     * or be an approved operator for `from`. `amount * rate()` underlying tokens are sent to `to`.
     *
     * Returns amount unwrapped.
     *
     * NOTE: The unwrap request created by this function must be finalized by calling {finalizeUnwrap}.
     * NOTE: The caller *must* already be approved by ACL for the given `amount`.
     */
    function unwrap(address from, address to, euint64 amount) public virtual returns (euint64) {
        require(FHE.isAllowed(amount, msg.sender), ERC7984UnauthorizedUseOfEncryptedAmount(amount, msg.sender));
        return _unwrap(from, to, amount);
    }

    /**
     * @dev Variant of {unwrap} that passes an `inputProof` which approves the caller for the `encryptedAmount`
     * in the ACL.
     *
     * Returns amount unwrapped.
     */
    function unwrap(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual returns (euint64) {
        return _unwrap(from, to, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /// @dev Fills an unwrap request for a given cipher-text `unwrapAmount` with the `cleartextAmount` and `decryptionProof`.
    function finalizeUnwrap(
        euint64 unwrapAmount,
        uint64 unwrapAmountCleartext,
        bytes calldata decryptionProof
    ) public virtual {
        address to = _unwrapRequests[unwrapAmount];
        require(to != address(0), InvalidUnwrapRequest(unwrapAmount));
        delete _unwrapRequests[unwrapAmount];

        bytes32[] memory handles = new bytes32[](1);
        handles[0] = euint64.unwrap(unwrapAmount);

        bytes memory cleartexts = abi.encode(unwrapAmountCleartext);

        FHE.checkSignatures(handles, cleartexts, decryptionProof);

        SafeERC20.safeTransfer(underlying(), to, unwrapAmountCleartext * rate());

        emit UnwrapFinalized(to, unwrapAmount, unwrapAmountCleartext);
    }

    /// @inheritdoc ERC7984
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Returns the rate at which the underlying token is converted to the wrapped token.
     * For example, if the `rate` is 1000, then 1000 units of the underlying token equal 1 unit of the wrapped token.
     */
    function rate() public view virtual returns (uint256) {
        return _rate;
    }

    /// @dev Returns the address of the underlying ERC-20 token that is being wrapped.
    function underlying() public view returns (IERC20) {
        return _underlying;
    }

    /**
     * @dev Returns the underlying balance divided by the {rate}, a value greater or equal to the actual
     * {confidentialTotalSupply}.
     *
     * NOTE: The return value of this function can be inflated by directly sending underlying tokens to the wrapper contract.
     * Reductions will lag compared to {confidentialTotalSupply} since it is updated on {unwrap} while this function updates
     * on {finalizeUnwrap}.
     */
    function inferredTotalSupply() public view virtual returns (uint256) {
        return underlying().balanceOf(address(this)) / rate();
    }

    /// @dev Returns the maximum total supply of wrapped tokens supported by the encrypted datatype.
    function maxTotalSupply() public view virtual returns (uint256) {
        return type(uint64).max;
    }

    function unwrapRequests(euint64 unwrapAmount) public view virtual returns (address) {
        return _unwrapRequests[unwrapAmount];
    }

    /**
     * @dev This function must revert if the new {confidentialTotalSupply} is invalid (overflow occurred).
     *
     * NOTE: Overflow can be detected here since the wrapper holdings are non-confidential. In other cases, it may be impossible
     * to infer total supply overflow synchronously. This function may revert even if the {confidentialTotalSupply} did
     * not overflow.
     */
    function _checkConfidentialTotalSupply() internal virtual {
        if (inferredTotalSupply() > maxTotalSupply()) {
            revert ERC7984TotalSupplyOverflow();
        }
    }

    /// @inheritdoc ERC7984
    function _update(address from, address to, euint64 amount) internal virtual override returns (euint64) {
        if (from == address(0)) {
            _checkConfidentialTotalSupply();
        }
        return super._update(from, to, amount);
    }

    /// @dev Internal logic for handling the creation of unwrap requests.
    function _unwrap(address from, address to, euint64 amount) internal virtual returns (euint64) {
        require(to != address(0), ERC7984InvalidReceiver(to));
        require(from == msg.sender || isOperator(from, msg.sender), ERC7984UnauthorizedSpender(from, msg.sender));

        // try to burn, see how much we actually got
        euint64 unwrapAmount = _burn(from, amount);
        FHE.makePubliclyDecryptable(unwrapAmount);

        assert(_unwrapRequests[unwrapAmount] == address(0));

        // WARNING: Storing unwrap requests in a mapping from cipher-text to address assumes that
        // cipher-texts are unique--this holds here but is not always true. Be cautious when assuming
        // cipher-text uniqueness.
        _unwrapRequests[unwrapAmount] = to;

        emit UnwrapRequested(to, unwrapAmount);
        return unwrapAmount;
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
