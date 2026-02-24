// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {FHE, ebool, euint64} from "@fhevm/solidity/lib/FHE.sol";
import {IERC7984} from "../../../../interfaces/IERC7984.sol";
import {ERC7984RwaComplianceModule} from "./ERC7984RwaComplianceModule.sol";

/**
 * @dev A transfer compliance module for confidential Real World Assets (RWAs) which limits the number of investors.
 */
abstract contract ERC7984RwaInvestorCapModule is ERC7984RwaComplianceModule {
    mapping(address => uint64) private _maxInvestorCounts;
    mapping(address => euint64) private _investorCounts;

    event MaxInvestorSet(address indexed token, uint64 maxInvestor);

    function onInstall(bytes calldata initData) public override {
        uint64 maxInvestorCount = abi.decode(initData, (uint64));
        _setMaxInvestorCount(msg.sender, maxInvestorCount);
        super.onInstall(initData);
    }

    /// @dev Sets max number of investors for the given token `token` to `maxInvestor`.
    function setMaxInvestorCount(address token, uint64 maxInvestorCount) public virtual onlyTokenAgent(token) {
        _setMaxInvestorCount(token, maxInvestorCount);
    }

    /// @dev Gets max number of investors for the given token `token`.
    function maxInvestorCounts(address token) public view virtual returns (uint64) {
        return _maxInvestorCounts[token];
    }

    /// @dev Gets current number of investors for the given token `token`.
    function investorCounts(address token) public view virtual returns (euint64) {
        return _investorCounts[token];
    }

    function _setMaxInvestorCount(address token, uint64 maxInvestorCount) internal {
        _maxInvestorCounts[token] = maxInvestorCount;
        emit MaxInvestorSet(token, maxInvestorCount);
    }

    /// @dev Internal function which checks if a transfer is compliant.
    function _isCompliantTransfer(
        address token,
        address from,
        address to,
        euint64 encryptedAmount
    ) internal override returns (ebool compliant) {
        if (to == address(0) || to == from || euint64.unwrap(encryptedAmount) == 0) {
            return FHE.asEbool(true);
        }

        euint64 fromBalance = IERC7984(token).confidentialBalanceOf(from);
        euint64 toBalance = IERC7984(token).confidentialBalanceOf(to);

        _getTokenHandleAllowance(token, fromBalance);
        _getTokenHandleAllowance(token, toBalance);

        require(FHE.isAllowed(fromBalance, token), UnauthorizedUseOfEncryptedAmount(fromBalance, token));
        require(FHE.isAllowed(toBalance, token), UnauthorizedUseOfEncryptedAmount(toBalance, token));
        require(FHE.isAllowed(encryptedAmount, token), UnauthorizedUseOfEncryptedAmount(encryptedAmount, token));

        compliant = FHE.or(
            FHE.eq(encryptedAmount, FHE.asEuint64(0)), // zero transfer
            FHE.or(
                FHE.gt(toBalance, FHE.asEuint64(0)), // already investor
                FHE.lt(investorCounts(token), maxInvestorCounts(token)) // room for another investor
            )
        );
    }

    /// @dev Internal function which performs operation after transfer.
    function _postTransfer(address token, address from, address to, euint64 encryptedAmount) internal override {
        euint64 fromBalance = IERC7984(token).confidentialBalanceOf(from);
        euint64 toBalance = IERC7984(token).confidentialBalanceOf(to);

        _getTokenHandleAllowance(token, fromBalance);
        _getTokenHandleAllowance(token, toBalance);

        require(FHE.isAllowed(encryptedAmount, token), UnauthorizedUseOfEncryptedAmount(encryptedAmount, token));
        require(FHE.isAllowed(fromBalance, token), UnauthorizedUseOfEncryptedAmount(fromBalance, msg.sender));
        require(FHE.isAllowed(toBalance, token), UnauthorizedUseOfEncryptedAmount(toBalance, msg.sender));

        ebool transferNotZero = FHE.ne(encryptedAmount, euint64.wrap(0));
        euint64 newInvestorCount = investorCounts(token);

        if (to != address(0)) {
            ebool addInvestor = FHE.and(transferNotZero, FHE.eq(toBalance, encryptedAmount));
            newInvestorCount = FHE.add(newInvestorCount, FHE.asEuint64(addInvestor));
        }

        if (from != address(0)) {
            ebool subInvestor = FHE.and(transferNotZero, FHE.eq(fromBalance, euint64.wrap(0)));
            newInvestorCount = FHE.sub(newInvestorCount, FHE.asEuint64(subInvestor));
        }

        _investorCounts[token] = newInvestorCount;
        FHE.allowThis(newInvestorCount);
    }
}
