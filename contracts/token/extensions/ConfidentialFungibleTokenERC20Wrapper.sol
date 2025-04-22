// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { TFHE, einput, euint64 } from "fhevm/lib/TFHE.sol";
import { Gateway } from "fhevm/gateway/lib/Gateway.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { IERC1363Receiver } from "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ConfidentialFungibleToken } from "../ConfidentialFungibleToken.sol";

abstract contract ConfidentialFungibleTokenERC20Wrapper is ConfidentialFungibleToken, IERC1363Receiver {
    using TFHE for *;
    using SafeCast for *;

    IERC20 private immutable _underlying;
    uint8 private immutable _decimals;
    uint256 private immutable _rate;

    /// @dev Mapping from gateway decryption request ID to the address that will receive the tokens
    mapping(uint256 decryptionRequest => address) private _receivers;

    error ConfidentialFungibleTokenERC20WrapperUnauthorizedCaller(address);
    error ConfidentialFungibleTokenERC20WrapperInvalidUnwrapRequest(uint256);
    error ConfidentialFungibleTokenERC20WrapperInvalidTokenRecipient(address);

    modifier onlyGateway() {
        require(
            msg.sender == Gateway.gatewayContractAddress(),
            ConfidentialFungibleTokenERC20WrapperUnauthorizedCaller(msg.sender)
        );
        _;
    }

    constructor(IERC20 underlying_) {
        _underlying = underlying_;

        uint8 tokenDecimals = _tryGetAssetDecimals(underlying_);
        if (tokenDecimals > 9) {
            _decimals = 9;
            _rate = 10 ** (tokenDecimals - 9);
        } else {
            _decimals = tokenDecimals;
            _rate = 1;
        }
    }

    function _tryGetAssetDecimals(IERC20 asset_) private view returns (uint8 assetDecimals) {
        (bool success, bytes memory encodedDecimals) = address(asset_).staticcall(
            abi.encodeCall(IERC20Metadata.decimals, ())
        );
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                return uint8(returnedDecimals);
            }
        }
        return 18;
    }

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

    function onTransferReceived(
        address /*operator*/,
        address from,
        uint256 value,
        bytes calldata data
    ) public virtual returns (bytes4) {
        // check caller is the token contract
        require(
            address(underlying()) == msg.sender,
            ConfidentialFungibleTokenERC20WrapperUnauthorizedCaller(msg.sender)
        );

        // transfer excess back to the sender
        uint256 excess = value % rate();
        if (excess > 0) SafeERC20.safeTransfer(underlying(), from, excess);

        // mint confidential token
        address to = data.length < 20 ? from : address(bytes20(data));
        _mint(to, (value / rate()).toUint64().asEuint64());

        // return magic value
        return IERC1363Receiver.onTransferReceived.selector;
    }

    function wrap(address to, uint256 value) public virtual {
        // take ownership of the tokens
        SafeERC20.safeTransferFrom(underlying(), msg.sender, address(this), value - (value % rate()));

        // mint confidential token
        _mint(to, (value / rate()).toUint64().asEuint64());
    }

    function unwrap(address from, address to, einput encryptedAmount, bytes calldata inputProof) public virtual {
        unwrap(from, to, encryptedAmount.asEuint64(inputProof));
    }

    function unwrap(address from, address to, euint64 amount) public virtual {
        require(to != address(0), ConfidentialFungibleTokenERC20WrapperInvalidTokenRecipient(to));
        require(
            amount.isAllowed(msg.sender),
            ConfidentialFungibleTokenUnauthorizedUseOfEncryptedValue(amount, msg.sender)
        );
        require(
            from == msg.sender || isOperator(from, msg.sender),
            ConfidentialFungibleTokenUnauthorizedSpender(from, msg.sender)
        );

        // try to burn, see how much we actually got
        euint64 burntAmount = _burn(from, amount);

        // decrypt that burntAmount
        uint256[] memory cts = new uint256[](1);
        cts[0] = euint64.unwrap(burntAmount);
        uint256 requestID = Gateway.requestDecryption(
            cts,
            this.finalizeUnwrap.selector,
            0,
            block.timestamp + 3600,
            false
        ); // max delay ?

        // register who is getting the tokens
        _receivers[requestID] = to;
    }

    function finalizeUnwrap(uint256 requestID, uint64 amount) public virtual onlyGateway {
        address to = _receivers[requestID];
        require(to != address(0), ConfidentialFungibleTokenERC20WrapperInvalidUnwrapRequest(requestID));
        delete _receivers[requestID];

        SafeERC20.safeTransfer(underlying(), to, amount * rate());
    }
}
