// SPDX-License-Identifier: MIT

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity ^0.8.27;

contract ProtocolOperatorRegistry {
    mapping(address => address) _operatorToStakedTokens;
    mapping(address => address) _stakedTokensToOperator;

    event StakedTokensAccountSet(address operator, address previousStakedTokensAccount, address newStakedTokensAccount);

    function setStakedTokensAccount(address account) public virtual {
        address currentStakedTokensAccount = stakedTokens(msg.sender);

        if (account == address(0)) {
            _stakedTokensToOperator[currentStakedTokensAccount] = address(0);
            _operatorToStakedTokens[msg.sender] = address(0);
            return;
        }

        require(Ownable(account).owner() == msg.sender);
        require(operator(account) == address(0));

        if (currentStakedTokensAccount != address(0)) {
            _stakedTokensToOperator[currentStakedTokensAccount] = address(0);
        }
        _stakedTokensToOperator[account] = msg.sender;
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
