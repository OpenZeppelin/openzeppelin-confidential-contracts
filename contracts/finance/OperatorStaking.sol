// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {OperatorStakingRewarder} from "./OperatorStakingRewarder.sol";
import {ProtocolStaking} from "./ProtocolStaking.sol";

contract OperatorStaking is ERC4626, Ownable {
    ProtocolStaking private _protocolStaking;

    constructor(
        string memory name,
        string memory symbol,
        ProtocolStaking protocolStaking
    ) ERC20(name, symbol) ERC4626(IERC20(protocolStaking.stakingToken())) Ownable(msg.sender) {
        _protocolStaking = protocolStaking;
        IERC20(protocolStaking.stakingToken()).approve(address(protocolStaking), type(uint256).max);
        setRewarder(address(new OperatorStakingRewarder(msg.sender, address(this))));
    }

    /// @dev Gets rewarder address.
    function rewarder() public view virtual returns (address) {
        return _protocolStaking.rewardsRecipient(address(this));
    }

    /// @dev Sets rewarder address.
    function setRewarder(address rewarder_) public virtual onlyOwner {
        _protocolStaking.setRewardsRecipient(rewarder_);
    }

    /// @dev Helper to restake immediately withdrawn rewards.
    function restakeRewards() public virtual {
        uint256 balanceBefore = IERC20(_protocolStaking).balanceOf(msg.sender);
        withdrawRewards(msg.sender);
        uint256 balanceAfter = IERC20(_protocolStaking).balanceOf(msg.sender);
        uint256 rewards = balanceAfter - balanceBefore;
        deposit(rewards, msg.sender);
    }

    /**
     * WARNING: This design only works with a non-negligible cooldown period on `ProtocolStaking` such that the jumps in `totalAssets`
     * upon claiming and disbursing rewards can't be gamed. If the cooldown period is small, `totalAssets` must count unclaimed rewards.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return super.totalAssets() + _protocolStaking.balanceOf(address(this));
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        super._deposit(caller, receiver, assets, shares);
        _protocolStaking.stake(assets);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);
        _protocolStaking.unstake(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @dev Helper to withdraw latest rewards.
    function withdrawRewards(address account) public virtual {
        _protocolStaking.claimRewards(address(this)); // will transfer to rewarder
        OperatorStakingRewarder(rewarder()).withdrawRewards(account);
    }
}
