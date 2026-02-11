// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {FHE, externalEuint64, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {BatcherConfidential} from "./../../utils/BatcherConfidential.sol";
import {ExchangeMock} from "./../finance/ExchangeMock.sol";

abstract contract BatcherConfidentialSwapMock is ZamaEthereumConfig, BatcherConfidential {
    ExchangeMock public exchange;
    address public admin;
    bool public setExchangeRate = true;

    constructor(ExchangeMock exchange_, address admin_) {
        exchange = exchange_;
        admin = admin_;
    }

    function routeDescription() public pure override returns (string memory) {
        return "Exchange fromToken for toToken by swapping through the mock exchange.";
    }

    function shouldSetExchangeRate(bool setExchangeRate_) public {
        setExchangeRate = setExchangeRate_;
    }

    function join(uint64 amount) public {
        euint64 ciphertext = FHE.asEuint64(amount);
        FHE.allowTransient(ciphertext, msg.sender);

        bytes memory callData = abi.encodePacked(
            BatcherConfidential.join.selector,
            abi.encode(externalEuint64.wrap(euint64.unwrap(ciphertext)), hex"")
        );

        (bool success, bytes memory returnVal) = address(this).delegatecall(callData);

        if (!success) {
            assembly ("memory-safe") {
                revert(add(0x20, returnVal), mload(returnVal))
            }
        }
    }

    function quit(uint256 batchId) public virtual override returns (euint64) {
        euint64 amount = super.quit(batchId);
        FHE.allow(totalDeposits(currentBatchId()), admin);
        return amount;
    }

    function _join(address to, euint64 amount) internal virtual override returns (euint64) {
        euint64 joinedAmount = super._join(to, amount);
        FHE.allow(totalDeposits(currentBatchId()), admin);
        return joinedAmount;
    }

    function _executeRoute(uint256, uint256 unwrapAmount) internal override returns (uint64) {
        // Approve exchange to spend unwrapped tokens
        uint256 rawAmount = unwrapAmount * fromToken().rate();
        IERC20(fromToken().underlying()).approve(address(exchange), rawAmount);

        // Swap unwrapped tokens via exchange
        uint256 swappedAmount = exchange.swapAToB(rawAmount);

        // excess over rate is essentially burned. Should be considered a fee that goes to the owner.
        IERC20(toToken().underlying()).approve(address(toToken()), swappedAmount);
        toToken().wrap(address(this), swappedAmount);

        uint256 amountOut = swappedAmount / toToken().rate();

        // Set the exchange rate for the batch based on swapped amount
        uint256 exchangeRate = (amountOut * (uint256(10) ** exchangeRateDecimals())) / unwrapAmount;

        if (setExchangeRate) return uint64(exchangeRate);
        return 0;
    }
}
