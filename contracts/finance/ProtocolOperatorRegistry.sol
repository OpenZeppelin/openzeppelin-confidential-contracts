// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice This contract creates a registry for validators to indicate which account holds their staked tokens.
contract ProtocolOperatorRegistry {
    mapping(address => address) private _operatorToStakedTokens;
    mapping(address => address) private _stakedTokensToOperator;

    event StakedTokensAccountSet(address operator, address previousStakedTokensAccount, address newStakedTokensAccount);

    error StakingAccountNotOwnedByCaller();
    error StakingAccountAlreadyRegistered();

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

    function operator(address account) public view returns (address) {
        return _stakedTokensToOperator[account];
    }

    function stakedTokens(address account) public view returns (address) {
        return _operatorToStakedTokens[account];
    }
}
