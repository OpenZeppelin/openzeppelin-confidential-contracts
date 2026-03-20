// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984Rwa} from "./../../../interfaces/IERC7984Rwa.sol";
import {ERC7984HookModule} from "./ERC7984HookModule.sol";

/// @dev A transfer compliance module for confidential Real World Assets (RWAs) which limits the number of investors.
abstract contract ERC7984InvestorCapHookModule is ERC7984HookModule {
    event MaxInvestorCountSet(address indexed token, uint64 maxInvestorCount);

    error Unauthorized();

    mapping(address => uint64) private _maxInvestorCounts;
    mapping(address => euint64) private _investorCounts;

    function onInstall(bytes calldata initData) public override {
        uint64 maxInvestorCount_ = abi.decode(initData, (uint64));
        _setMaxInvestorCount(msg.sender, maxInvestorCount_);
        super.onInstall(initData);
    }

    /// @dev Sets the max number of investors for the given token `token` to `maxInvestorCount_`.
    function setMaxInvestorCount(address token, uint64 maxInvestorCount_) public virtual {
        require(IERC7984Rwa(token).isAgent(msg.sender), Unauthorized());
        _setMaxInvestorCount(token, maxInvestorCount_);
    }

    /// @dev Gets max number of investors for the given token `token`.
    function maxInvestorCount(address token) public view virtual returns (uint64) {
        return _maxInvestorCounts[token];
    }

    /// @dev Gets current number of investors for the given token `token`.
    function investorCount(address token) public view virtual returns (euint64) {
        return _investorCounts[token];
    }

    function _setMaxInvestorCount(address token, uint64 maxInvestorCount_) internal {
        _maxInvestorCounts[token] = maxInvestorCount_;
        emit MaxInvestorCountSet(token, maxInvestorCount_);
    }

    /// @inheritdoc ERC7984HookModule
    function _preTransfer(
        address token,
        address from,
        address to,
        euint64 encryptedAmount
    ) internal override returns (ebool) {
        if (to == address(0) || to == from || !FHE.isInitialized(encryptedAmount)) {
            return FHE.asEbool(true);
        }

        euint64 fromBalance = IERC7984Rwa(token).confidentialBalanceOf(from);
        euint64 toBalance = IERC7984Rwa(token).confidentialBalanceOf(to);

        _getTokenHandleAllowance(token, fromBalance);
        _getTokenHandleAllowance(token, toBalance);

        if (FHE.isInitialized(fromBalance))
            require(
                FHE.isAllowed(fromBalance, token),
                ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(fromBalance, token)
            );
        if (FHE.isInitialized(toBalance))
            require(
                FHE.isAllowed(toBalance, token),
                ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(toBalance, token)
            );

        euint64 encryptedZero = FHE.asEuint64(0);

        // Note, not checking if current transfer is the whole balance of the from address
        return
            FHE.or(
                FHE.eq(encryptedAmount, encryptedZero), // zero transfer
                FHE.or(
                    FHE.ne(toBalance, encryptedZero), // already investor
                    FHE.lt(investorCount(token), maxInvestorCount(token)) // room for another investor
                )
            );
    }

    /// @inheritdoc ERC7984HookModule
    function _postTransfer(address token, address from, address to, euint64 encryptedAmount) internal override {
        euint64 fromBalance = IERC7984Rwa(token).confidentialBalanceOf(from);
        euint64 toBalance = IERC7984Rwa(token).confidentialBalanceOf(to);

        _getTokenHandleAllowance(token, fromBalance);
        _getTokenHandleAllowance(token, toBalance);

        if (FHE.isInitialized(fromBalance))
            require(
                FHE.isAllowed(fromBalance, token),
                ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(fromBalance, token)
            );
        if (FHE.isInitialized(toBalance))
            require(
                FHE.isAllowed(toBalance, token),
                ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(toBalance, token)
            );

        euint64 encryptedZero = FHE.asEuint64(0);
        ebool transferNotZero = FHE.ne(encryptedAmount, encryptedZero);
        euint64 newInvestorCount = investorCount(token);

        if (to != address(0)) {
            ebool addInvestor = FHE.and(transferNotZero, FHE.eq(toBalance, encryptedAmount));
            newInvestorCount = FHE.add(newInvestorCount, FHE.asEuint64(addInvestor));
        }

        if (from != address(0)) {
            ebool subInvestor = FHE.and(transferNotZero, FHE.eq(fromBalance, encryptedZero));
            newInvestorCount = FHE.sub(newInvestorCount, FHE.asEuint64(subInvestor));
        }

        _investorCounts[token] = newInvestorCount;
        FHE.allowThis(newInvestorCount);
    }
}
