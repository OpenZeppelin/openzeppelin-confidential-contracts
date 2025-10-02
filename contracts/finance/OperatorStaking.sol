// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ProtocolStaking} from "./ProtocolStaking.sol";
import {StakersRewardsRecipient} from "./StakersRewardsRecipient.sol";

contract OperatorStaking is ERC4626, Ownable {
    ProtocolStaking private _protocolStaking;
    StakersRewardsRecipient private _stakersRewardsRecipient;

    constructor(
        string memory name,
        string memory symbol,
        ProtocolStaking protocolStaking
    ) ERC20(name, symbol) ERC4626(IERC20(protocolStaking.stakingToken())) Ownable(msg.sender) {
        _protocolStaking = protocolStaking;
        IERC20(protocolStaking.stakingToken()).approve(address(protocolStaking), type(uint256).max);
    }

    /// @dev Gets rewarder address.
    function globalRewardsRecipient() public view virtual returns (address) {
        return _protocolStaking.rewardsRecipient(address(this));
    }

    /// @dev Sets reward recipient.
    function setGlobalRewardsRecipient(address globalRewardsRecipient_) public virtual onlyOwner {
        _protocolStaking.setGlobalRewardsRecipient(globalRewardsRecipient_);
    }

    function setStakersRewardsRecipient(address stakersRewardsRecipient) public virtual onlyOwner {
        _stakersRewardsRecipient = StakersRewardsRecipient(stakersRewardsRecipient);
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
        // Cannot claim past rewards for these new shares, so we virtually release this delta for caller
        _stakersRewardsRecipient.increaseReleasedRewards(caller, shares, totalSupply());
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
        withdrawRewards(owner); // withdraw rewards before burning some shares (will reward global recipient)
        // Allow future withdraws by removing previously claimed reward delta related to burn shares
        _stakersRewardsRecipient.decreaseReleasedRewards(owner, shares, totalSupply());
        _burn(owner, shares);
        _protocolStaking.unstake(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @dev Helper to withdraw latest rewards.
    function withdrawRewards(address account) public virtual {
        _protocolStaking.claimRewards(address(this)); // will transfer to rewarder
        _stakersRewardsRecipient.withdrawRewards(account, balanceOf(account), totalSupply());
    }
}
