// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ProtocolStaking} from "./ProtocolStaking.sol";
import {IPaymentSplitter, StakersRewardsRecipient} from "./StakersRewardsRecipient.sol";

/**
 * An {OperatorStaking} contracts that allows accounts (stakers) to deposit staking tokens onto.
 * Deposits from stakers are restaked by this operator contract on the related {ProtocolStaking} contract.
 */
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

    /// @dev Gets global rewards recipient address.
    function globalRewardsRecipient() public view virtual returns (address) {
        return _protocolStaking.rewardsRecipient(address(this));
    }

    /// @dev Sets global rewards recipient address.
    function setGlobalRewardsRecipient(address globalRewardsRecipient_) public virtual onlyOwner {
        _protocolStaking.setGlobalRewardsRecipient(globalRewardsRecipient_);
    }

    /// @dev Gets stakers rewards recipient address.
    function stakersRewardsRecipient() public view virtual returns (address) {
        return address(_stakersRewardsRecipient);
    }

    /// @dev Sets stakers rewards recipient address.
    function setStakersRewardsRecipient(address stakersRewardsRecipient) public virtual onlyOwner {
        _stakersRewardsRecipient = StakersRewardsRecipient(stakersRewardsRecipient);
    }

    /// @dev Withdraw rewards.
    function withdrawRewards(address account) public virtual {
        if (account == owner()) {
            // Withdraw operator rewards
            IPaymentSplitter globalRewardsRecipient_ = IPaymentSplitter(globalRewardsRecipient());
            IERC20 stakingToken_ = IERC20(_protocolStaking.stakingToken());
            if (globalRewardsRecipient_.releasable(stakingToken_, address(this)) > 0) {
                globalRewardsRecipient_.release(stakingToken_, address(this));
            }
        } else {
            // Withdraw staker rewards
            _protocolStaking.claimRewards(address(this)); // Transfer all rewards to global rewards recipient
            _stakersRewardsRecipient.withdrawRewards(account, balanceOf(account), totalSupply()); // Get staker rewards
        }
    }

    /// @dev Restake pending rewards of staker.
    function restakeRewards() public virtual {
        uint256 balanceBefore = _protocolStaking.balanceOf(msg.sender);
        withdrawRewards(msg.sender);
        deposit(_protocolStaking.balanceOf(msg.sender) - balanceBefore, msg.sender);
    }

    /**
     * WARNING: This design only works with a non-negligible cooldown period on `ProtocolStaking` such that the jumps in `totalAssets`
     * upon claiming and disbursing rewards can't be gamed. If the cooldown period is small, `totalAssets` must count unclaimed rewards.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return super.totalAssets() + _protocolStaking.balanceOf(address(this));
    }

    /// @inheritdoc ERC4626
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        // Past rewards for these new shares cannot be claimed, hence the delta is virtually released for the caller
        _stakersRewardsRecipient.increaseReleasedRewards(caller, shares, totalSupply());
        super._deposit(caller, receiver, assets, shares);
        _protocolStaking.stake(assets);
    }

    /// @inheritdoc ERC4626
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
        withdrawRewards(owner); // Withdraw pending rewards before these shares are burn
        // Allow future withdraws by removing previously claimed rewards delta related to burn shares
        _stakersRewardsRecipient.decreaseReleasedRewards(owner, shares, totalSupply());
        _burn(owner, shares);
        _protocolStaking.unstake(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
