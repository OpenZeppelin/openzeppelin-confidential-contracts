// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984Rwa} from "./../../../interfaces/IERC7984Rwa.sol";
import {ERC7984HookModule} from "./ERC7984HookModule.sol";

/// @dev A transfer compliance module for confidential Real World Assets (RWAs) which limits the number of investors.
abstract contract InvestorCapComplianceModuleConfidential is ERC7984HookModule {
    mapping(address => uint64) private _maxInvestors;
    mapping(address => euint64) private _investorCounts;

    error Unauthorized();

    event MaxInvestorSet(address indexed token, uint64 maxInvestor);

    function onInstall(bytes calldata initData) public override {
        uint64 maxInvestorCount = abi.decode(initData, (uint64));
        _setMaxInvestors(msg.sender, maxInvestorCount);
        super.onInstall(initData);
    }

    /// @dev Sets max number of investors for the given token `token` to `maxInvestor`.
    function setMaxInvestors(address token, uint64 maxInvestors_) public virtual {
        require(IERC7984Rwa(token).isAgent(msg.sender), Unauthorized());
        _setMaxInvestors(token, maxInvestors_);
    }

    /// @dev Gets max number of investors for the given token `token`.
    function maxInvestors(address token) public view virtual returns (uint64) {
        return _maxInvestors[token];
    }

    /// @dev Gets current number of investors for the given token `token`.
    function investorCounts(address token) public view virtual returns (euint64) {
        return _investorCounts[token];
    }

    function _setMaxInvestors(address token, uint64 maxInvestorCount) internal {
        _maxInvestors[token] = maxInvestorCount;
        emit MaxInvestorSet(token, maxInvestorCount);
    }

    /// @inheritdoc ERC7984HookModule
    function _preTransfer(
        address token,
        address from,
        address to,
        euint64 encryptedAmount
    ) internal override returns (ebool) {
        if (to == address(0) || to == from || euint64.unwrap(encryptedAmount) == 0) {
            return FHE.asEbool(true);
        }

        euint64 fromBalance = IERC7984Rwa(token).confidentialBalanceOf(from);
        euint64 toBalance = IERC7984Rwa(token).confidentialBalanceOf(to);

        _getTokenHandleAllowance(token, fromBalance);
        _getTokenHandleAllowance(token, toBalance);

        require(
            FHE.isAllowed(fromBalance, token),
            ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(fromBalance, token)
        );
        require(FHE.isAllowed(toBalance, token), ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(toBalance, token));

        euint64 encryptedZero = FHE.asEuint64(0);

        // Note, not checking if current transfer is the whole balance of the from address
        return
            FHE.or(
                FHE.eq(encryptedAmount, encryptedZero), // zero transfer
                FHE.or(
                    FHE.ne(toBalance, encryptedZero), // already investor
                    FHE.lt(investorCounts(token), maxInvestors(token)) // room for another investor
                )
            );
    }

    /// @inheritdoc ERC7984HookModule
    function _postTransfer(address token, address from, address to, euint64 encryptedAmount) internal override {
        euint64 fromBalance = IERC7984Rwa(token).confidentialBalanceOf(from);
        euint64 toBalance = IERC7984Rwa(token).confidentialBalanceOf(to);

        _getTokenHandleAllowance(token, fromBalance);
        _getTokenHandleAllowance(token, toBalance);

        require(
            FHE.isAllowed(fromBalance, token),
            ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(fromBalance, msg.sender)
        );
        require(
            FHE.isAllowed(toBalance, token),
            ERC7984HookModuleUnauthorizedUseOfEncryptedAmount(toBalance, msg.sender)
        );

        euint64 encryptedZero = FHE.asEuint64(0);
        ebool transferNotZero = FHE.ne(encryptedAmount, encryptedZero);
        euint64 newInvestorCount = investorCounts(token);

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
