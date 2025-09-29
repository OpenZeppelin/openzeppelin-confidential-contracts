// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OperatorStakingRewarder} from "./OperatorStakingRewarder.sol";

interface IProtocolStaking {
    function stakingToken() external view returns (address);
    function releasable(address account) external view returns (uint256);
    function rewardsRecipient(address account) external view returns (address);
    function setRewardsRecipient(address recipient) external;
    function stake(uint256 amount) external;
    function unstake(address recipient, uint256 amount) external;
    function release(address account) external;
    function claimRewards(address account) external;
}

interface IOperatorStakingRewarder {
    function claim(address account) external;
    function initRewardState(address account, uint256 shares) external;
}

/**
 * @dev A contract to allow holders to deposits tokens that can be staked on the protocol by the operator.
 */
abstract contract OperatorStaking is ERC20, Ownable {
    using SafeERC20 for IERC20;

    address private immutable _protocolStaking;

    event Staked(uint256 amount);
    event Deposited(address account, uint256 amount);
    event WithdrawRequested(address account, uint256 amount);
    event Withdrawn(address account, uint256 amount);

    error StakingTooMuch();
    error RequestingTooMuchWithdrawal();

    constructor(
        address protocolStaking,
        address owner,
        string memory assetName,
        string memory assetSymbol
    ) Ownable(owner) ERC20(assetName, assetSymbol) {
        _protocolStaking = protocolStaking;
        setRewarder(address(new OperatorStakingRewarder(owner, address(this))));
    }

    /// @dev Gets underlying asset address.
    function asset() public view virtual returns (address) {
        return IProtocolStaking(_protocolStaking).stakingToken();
    }

    /// @dev Gets rewarder address.
    function rewarder() public view virtual returns (address) {
        return IProtocolStaking(_protocolStaking).rewardsRecipient(address(this));
    }

    /// @dev Sets rewarder address.
    function setRewarder(address rewarder_) public virtual onlyOwner {
        IProtocolStaking(_protocolStaking).setRewardsRecipient(rewarder_);
    }

    /// @dev Stakes on protocol the full or partial amount of tokens deposited by holders.
    function stake(uint256 amount) public virtual onlyOwner {
        _stake(amount);
    }

    /// @dev Deposits an amount of tokens that can be later staked by the operator on the protocol.
    function deposit(uint256 amount) public {
        require(IERC20(asset()).transferFrom(msg.sender, address(this), amount));
        IOperatorStakingRewarder(rewarder()).initRewardState(msg.sender, amount);
        _mint(msg.sender, amount);
        emit Deposited(msg.sender, amount);
    }

    /// @dev Claim rewards for deposits made by holders.
    function claimRewards(address account) public virtual {
        IOperatorStakingRewarder(rewarder()).claim(account);
    }

    /**
     * @dev Request to withdraw a deposited amount of tokens that can be fully received
     * with {withdraw} after the protocol cooldown period.
     */
    function requestWithdraw(uint256 amount) public virtual {
        require(amount <= balanceOf(msg.sender), RequestingTooMuchWithdrawal());
        claimRewards(msg.sender); // claim rewards before shares are burned
        _burn(msg.sender, amount);
        IProtocolStaking(_protocolStaking).unstake(msg.sender, amount);
        //TODO: Handle re-entry
        emit WithdrawRequested(msg.sender, amount);
    }

    /// @dev Withdraw an amount of deposited tokens. See {requestWithdraw}.
    function withdraw(uint256 amount) public virtual {
        IProtocolStaking(_protocolStaking).release(msg.sender);
        emit Withdrawn(msg.sender, amount);
    }

    /// @dev Internal function which stakes on protocol the full or partial amount of tokens deposited by holders.
    function _stake(uint256 amount) internal virtual {
        IERC20 asset_ = IERC20(asset());
        require(amount <= asset_.balanceOf(address(this)), StakingTooMuch());
        asset_.approve(_protocolStaking, amount);
        IProtocolStaking(_protocolStaking).stake(amount);
        emit Staked(amount);
    }
}
