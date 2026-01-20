// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";
import {BatcherConfidential} from "../../utils/BatcherConfidential.sol";
import {ExchangeMock} from "../finance/ExchangeMock.sol";

abstract contract BatcherConfidentialSwapMock is ZamaEthereumConfig, BatcherConfidential {
    ExchangeMock public exchange;

    constructor(ExchangeMock exchange_) {
        exchange = exchange_;
    }

    function _executeRoute(uint256 batchId, uint256 unwrapAmount) internal override {
        // Approve exchange to spend unwrapped tokens
        fromToken().underlying().approve(address(exchange), unwrapAmount);

        // Swap unwrapped tokens via exchange
        uint256 swappedAmount = exchange.swapAToB(unwrapAmount);

        toToken().underlying().approve(address(toToken()), swappedAmount);
        toToken().wrap(address(this), swappedAmount);

        // Set the exchange rate for the batch based on swapped amount
        uint256 exchangeRate = (swappedAmount * 1e18) / unwrapAmount;
        _setExchangeRate(batchId, exchangeRate);
    }
}
