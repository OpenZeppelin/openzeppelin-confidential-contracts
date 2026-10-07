// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {BatcherConfidential} from "./../../finance/BatcherConfidential.sol";
import {ExchangeMock} from "./../finance/ExchangeMock.sol";

/// @dev The exposed mint of `$ERC20Mock`, used to simulate an external service delivering tokens.
interface IERC20MintMock {
    // solhint-disable-next-line func-name-mixedcase
    function $_mint(address to, uint256 value) external;
}

abstract contract BatcherConfidentialSwapMock is ZamaEthereumConfig, BatcherConfidential {
    enum RouteMode {
        Swap, // Swap through the exchange and receive the outcome in the same call
        Send, // Send the input to the exchange and receive the outcome later
        Revert, // Revert
        KeepInput, // Return without spending the input
        SendAndReceive, // Swap through the exchange but report the outcome as not received
        BurnGasThenSwap // Burn gas before swapping
    }

    ExchangeMock public exchange;
    address public admin;
    RouteMode public routeMode = RouteMode.Swap;
    bool public outcomeReceived;
    bool public settleReceivesToToken;

    error RouteReverted();

    constructor(ExchangeMock exchange_, address admin_) {
        exchange = exchange_;
        admin = admin_;
    }

    function routeDescription() public pure override returns (string memory) {
        return "Exchange fromToken for toToken by swapping through the mock exchange.";
    }

    function setRouteMode(RouteMode routeMode_) public {
        routeMode = routeMode_;
    }

    function setOutcomeReceived(bool value) public {
        outcomeReceived = value;
    }

    function setSettleReceivesToToken(bool value) public {
        settleReceivesToToken = value;
    }

    /// @dev Join the current batch with `externalAmount` and `inputProof`.
    function join(externalEuint64 externalAmount, bytes calldata inputProof) public virtual returns (euint64) {
        euint64 amount = FHE.fromExternal(externalAmount, inputProof);
        FHE.allowTransient(amount, address(fromToken()));
        euint64 transferred = fromToken().confidentialTransferFrom(msg.sender, address(this), amount);

        euint64 joinedAmount = _join(msg.sender, transferred);
        euint64 refundAmount = FHE.sub(transferred, joinedAmount);

        FHE.allowTransient(refundAmount, address(fromToken()));

        fromToken().confidentialTransfer(msg.sender, refundAmount);

        return joinedAmount;
    }

    function join(uint64 amount) public {
        euint64 ciphertext = FHE.asEuint64(amount);
        FHE.allowTransient(ciphertext, msg.sender);

        bytes memory callData = abi.encodeWithSignature(
            "join(bytes32,bytes)",
            externalEuint64.wrap(euint64.unwrap(ciphertext)),
            hex""
        );

        Address.functionDelegateCall(address(this), callData);
    }

    function quit(uint256 batchId) public virtual override returns (euint64) {
        euint64 amount = super.quit(batchId);
        FHE.allow(totalDeposits(batchId), admin);
        return amount;
    }

    function _join(address to, euint64 amount) internal virtual override returns (euint64) {
        euint64 joinedAmount = super._join(to, amount);
        FHE.allow(totalDeposits(currentBatchId()), admin);
        return joinedAmount;
    }

    function _executeRoute(uint256, uint256 unwrapAmount) internal override returns (bool) {
        uint256 rawAmount = unwrapAmount * fromToken().rate();
        RouteMode mode = routeMode;

        if (mode == RouteMode.Revert) revert RouteReverted();
        if (mode == RouteMode.KeepInput) return false;
        if (mode == RouteMode.Send) {
            IERC20(fromToken().underlying()).transfer(address(exchange), rawAmount);
            return false;
        }
        if (mode == RouteMode.BurnGasThenSwap) {
            for (uint256 i = 0; i < 200; ++i) {
                assembly ("memory-safe") {
                    sstore(add(0x1000, i), add(i, 1))
                }
            }
        }

        IERC20(fromToken().underlying()).approve(address(exchange), rawAmount);
        exchange.swapAToB(rawAmount);
        return mode != RouteMode.SendAndReceive;
    }

    function _settleRoute(uint256, uint256) internal override returns (bool) {
        if (settleReceivesToToken) IERC20MintMock(toToken().underlying()).$_mint(address(this), 1);
        return outcomeReceived;
    }
}
