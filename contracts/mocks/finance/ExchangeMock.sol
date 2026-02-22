// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract ExchangeMock {
    IERC20 public tokenA;
    IERC20 public tokenB;
    uint256 public exchangeRate;

    event ExchangeRateSet(uint256 oldExchangeRate, uint256 newExchangeRate);

    constructor(IERC20 tokenA_, IERC20 tokenB_, uint256 initialExchangeRate) {
        tokenA = tokenA_;
        tokenB = tokenB_;
        exchangeRate = initialExchangeRate;
    }

    function swapAToB(uint256 amount) public returns (uint256) {
        uint256 amountOut = (amount * exchangeRate) / 1e18;
        require(tokenA.transferFrom(msg.sender, address(this), amount), "Transfer of token A failed");
        require(tokenB.transfer(msg.sender, amountOut), "Transfer of token B failed");
        return amountOut;
    }

    function swapBToA(uint256 amount) public returns (uint256) {
        uint256 amountOut = (amount * 1e18) / exchangeRate;
        require(tokenB.transferFrom(msg.sender, address(this), amount), "Transfer of token B failed");
        require(tokenA.transfer(msg.sender, amountOut), "Transfer of token A failed");
        return amountOut;
    }

    function setExchangeRate(uint256 newExchangeRate) public {
        emit ExchangeRateSet(exchangeRate, newExchangeRate);

        exchangeRate = newExchangeRate;
    }
}
