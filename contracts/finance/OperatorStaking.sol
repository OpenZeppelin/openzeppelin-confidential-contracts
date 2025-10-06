// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {ProtocolStaking} from "./ProtocolStaking.sol";
import {IPaymentSplitter, StakersRewardsRecipient} from "./StakersRewardsRecipient.sol";

/**
 * An {OperatorStaking} contracts that allows accounts (stakers) to deposit staking tokens onto.
 * Deposits from stakers are restaked by this operator contract on the related {ProtocolStaking} contract.
 */
contract OperatorStaking is ERC4626, Ownable {
    using Checkpoints for Checkpoints.Trace208;
    using SafeERC20 for IERC20;

    ProtocolStaking private immutable _protocolStaking;
    StakersRewardsRecipient private _stakersRewardsRecipient;
    mapping(address => Checkpoints.Trace208) private _unstakeRequests;
    mapping(address => uint256) private _released;

    constructor(
        string memory name,
        string memory symbol,
        ProtocolStaking protocolStaking,
        address admin
    ) ERC20(name, symbol) ERC4626(IERC20(protocolStaking.stakingToken())) Ownable(admin) {
        _protocolStaking = protocolStaking;
        IERC20(protocolStaking.stakingToken()).approve(address(protocolStaking), type(uint256).max);
    }

    /// @dev Gets protocol staking address.
    function protocolStaking() public view virtual returns (address) {
        return address(_protocolStaking);
    }

    /// @dev Gets global rewards recipient address.
    function globalRewardsRecipient() public view virtual returns (address) {
        return _protocolStaking.rewardsRecipient(address(this));
    }

    /// @dev Sets global rewards recipient address.
    function setGlobalRewardsRecipient(address globalRewardsRecipient_) public virtual onlyOwner {
        _protocolStaking.setRewardsRecipient(globalRewardsRecipient_);
    }

    /// @dev Gets stakers rewards recipient address.
    function stakersRewardsRecipient() public view virtual returns (address) {
        return address(_stakersRewardsRecipient);
    }

    /// @dev Sets stakers rewards recipient address.
    function setStakersRewardsRecipient(address stakersRewardsRecipient) public virtual onlyOwner {
        _stakersRewardsRecipient = StakersRewardsRecipient(stakersRewardsRecipient);
    }

    /// @dev Returns the amount of tokens cooling down for the given account `account`.
    function tokensInCooldown(address account) public view virtual returns (uint256) {
        return _unstakeRequests[account].latest() - _released[account];
    }

    /// @dev Releases tokens after unstake cooldown period.
    function release(address account) public virtual {
        uint256 amountToRelease = _unstakeRequests[account].upperLookup(Time.timestamp()) - _released[account];
        if (amountToRelease > 0) {
            _protocolStaking.release(address(this));
            _released[account] += amountToRelease;
            IERC20(asset()).safeTransfer(account, amountToRelease);
        }
    }

    /// @dev Withdraw rewards.
    function withdrawRewards(address account) public virtual {
        _protocolStaking.claimRewards(address(this)); // Transfer all rewards to global rewards recipient
        if (account == owner()) {
            // Withdraw operator rewards
            IPaymentSplitter globalRewardsRecipient_ = IPaymentSplitter(globalRewardsRecipient());
            IERC20 stakingToken_ = IERC20(asset());
            if (globalRewardsRecipient_.releasable(stakingToken_, owner()) > 0) {
                globalRewardsRecipient_.release(stakingToken_, owner());
            }
        } else {
            // Withdraw staker rewards
            _stakersRewardsRecipient.withdrawRewards(account, balanceOf(account), totalSupply());
        }
    }

    /// @dev Restake pending rewards of staker.
    function restakeRewards() public virtual {
        IERC20 stakingToken = IERC20(asset());
        uint256 balanceBefore = stakingToken.balanceOf(msg.sender);
        withdrawRewards(msg.sender);
        deposit(stakingToken.balanceOf(msg.sender) - balanceBefore, msg.sender);
    }

    /**
     * WARNING: This design only works with a non-negligible cooldown period on `ProtocolStaking` such that the jumps in `totalAssets`
     * upon claiming and disbursing rewards can't be gamed. If the cooldown period is small, `totalAssets` must count unclaimed rewards.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return
            super.totalAssets() +
            _protocolStaking.balanceOf(address(this)) +
            _protocolStaking.tokensInCooldown(address(this));
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
        _protocolStaking.unstake(address(this), assets);
        (, uint256 lastReleaseTime, uint256 totalRequestedToWithdraw) = _unstakeRequests[receiver].latestCheckpoint();
        uint256 releaseTime = Time.timestamp() + _protocolStaking.unstakeCooldownPeriod();
        _unstakeRequests[receiver].push(
            uint48(Math.max(releaseTime, lastReleaseTime)),
            uint208(totalRequestedToWithdraw + assets)
        );

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @dev Updates shares by virtually realeasing rewards related to new shares of `to` to prevent reward claim.
    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && to != address(0)) {
            withdrawRewards(from); // Withdraw pending rewards before these shares are transferred
            _stakersRewardsRecipient.increaseReleasedRewards(to, value, totalSupply());
        }
        super._update(from, to, value);
    }
}
