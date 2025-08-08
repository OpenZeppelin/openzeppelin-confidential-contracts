// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC1363Receiver} from "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ConfidentialFungibleToken} from "./../ConfidentialFungibleToken.sol";

/**
 * @dev A wrapper contract built on top of {ConfidentialFungibleToken} that allows wrapping an `ERC20` token
 * into a confidential fungible token. The wrapper contract implements the `IERC1363Receiver` interface
 * which allows users to transfer `ERC1363` tokens directly to the wrapper with a callback to wrap the tokens.
 *
 * WARNING: Minting assumes the full amount of the underlying token transfer has been received, hence some non-standard
 * tokens such as fee-on-transfer or other deflationary-type tokens are not supported by this wrapper.
 */
abstract contract ConfidentialFungibleTokenERC20Wrapper is ConfidentialFungibleToken, IERC1363Receiver {
    IERC20 private immutable _underlying;
    uint8 private immutable _decimals;
    uint256 private immutable _rate;

    /// @dev Mapping from gateway decryption request ID to the address that will receive the tokens
    mapping(uint256 decryptionRequest => address) private _receivers;

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

    /// @inheritdoc ConfidentialFungibleToken
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
     * @dev `ERC1363` callback function which wraps tokens to the address specified in `data` or
     * the address `from` (if no address is specified in `data`). This function refunds any excess tokens
     * sent beyond the nearest multiple of {rate}. See {wrap} from more details on wrapping tokens.
     */
    function onTransferReceived(
        address /*operator*/,
        address from,
        uint256 amount,
        bytes calldata data
    ) public virtual returns (bytes4) {
        // check caller is the token contract
        require(address(underlying()) == msg.sender, ConfidentialFungibleTokenUnauthorizedCaller(msg.sender));

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
     * NOTE: This is an asynchronous function and waits for decryption to be completed off-chain before disbursing
     * tokens.
     * NOTE: The caller *must* already be approved by ACL for the given `amount`.
     */
    function unwrap(address from, address to, euint64 amount) public virtual {
        require(
            FHE.isAllowed(amount, msg.sender),
            ConfidentialFungibleTokenUnauthorizedUseOfEncryptedAmount(amount, msg.sender)
        );
        _unwrap(from, to, amount);
    }

    /**
     * @dev Variant of {unwrap} that passes an `inputProof` which approves the caller for the `encryptedAmount`
     * in the ACL.
     */
    function unwrap(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) public virtual {
        _unwrap(from, to, FHE.fromExternal(encryptedAmount, inputProof));
    }

    /**
     * @dev Fills an unwrap request for a given request id related to a decrypted unwrap amount.
     */
    function finalizeUnwrap(uint256 requestID, uint64 amount, bytes[] memory signatures) public virtual {
        FHE.checkSignatures(requestID, signatures);
        address to = _receivers[requestID];
        require(to != address(0), ConfidentialFungibleTokenInvalidGatewayRequest(requestID));
        delete _receivers[requestID];

        SafeERC20.safeTransfer(underlying(), to, amount * rate());
    }

    function _unwrap(address from, address to, euint64 amount) internal virtual {
        require(to != address(0), ConfidentialFungibleTokenInvalidReceiver(to));
        require(
            from == msg.sender || isOperator(from, msg.sender),
            ConfidentialFungibleTokenUnauthorizedSpender(from, msg.sender)
        );

        // try to burn, see how much we actually got
        euint64 burntAmount = _burn(from, amount);

        // decrypt that burntAmount
        bytes32[] memory cts = new bytes32[](1);
        cts[0] = euint64.unwrap(burntAmount);
        uint256 requestID = FHE.requestDecryption(cts, this.finalizeUnwrap.selector);

        // register who is getting the tokens
        _receivers[requestID] = to;
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
