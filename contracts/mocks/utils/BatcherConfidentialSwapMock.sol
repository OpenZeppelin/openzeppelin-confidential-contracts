// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {BatcherConfidential} from "../../utils/BatcherConfidential.sol";
import {ExchangeMock} from "../finance/ExchangeMock.sol";

abstract contract BatcherConfidentialSwapMock is ZamaEthereumConfig, BatcherConfidential {
    ExchangeMock public exchange;

    constructor(ExchangeMock exchange_) {
        exchange = exchange_;
    }

    function _executeRoute(uint256 batchId, uint256 unwrapAmount) internal override {
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
        uint256 exchangeRate = (amountOut * 1e18) / unwrapAmount;
        _setExchangeRate(batchId, exchangeRate);
    }
}
