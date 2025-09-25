// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @dev This contract creates a registry for operator to indicate which account holds their staked tokens.
contract ProtocolOperatorRegistry {
    mapping(address => address) private _operatorToStakedTokens;
    mapping(address => address) private _stakedTokensToOperator;

    event StakedTokensAccountSet(address operator, address previousStakedTokensAccount, address newStakedTokensAccount);

    error StakingAccountNotOwnedByCaller();
    error StakingAccountAlreadyRegistered();

    /**
     * @dev Sets the staked tokens account for an operator `msg.sender`. Operators my unset their
     * staked tokens account by calling this function with `address(0)`.
     *
     * Requirements:
     *
     * - `msg.sender` must be the {Ownable-owner} of `account`.
     * - `account` must not already be claimed by another operator.
     */
    function setStakedTokensAccount(address account) public virtual {
        if (account != address(0)) {
            require(Ownable(account).owner() == msg.sender, StakingAccountNotOwnedByCaller());
            require(operator(account) == address(0), StakingAccountAlreadyRegistered());

            _stakedTokensToOperator[account] = msg.sender;
        }

        address currentStakedTokensAccount = stakedTokens(msg.sender);
        if (currentStakedTokensAccount != address(0)) {
            _stakedTokensToOperator[currentStakedTokensAccount] = address(0);
        }
        _operatorToStakedTokens[msg.sender] = account;

        emit StakedTokensAccountSet(msg.sender, currentStakedTokensAccount, account);
    }

    /// @dev Staked tokens account associated with a given operator account.
    function stakedTokens(address account) public view returns (address) {
        return _operatorToStakedTokens[account];
    }

    /// @dev Gets operator account associated with a given staked tokens account.
    function operator(address account) public view returns (address) {
        return _stakedTokensToOperator[account];
    }
}
