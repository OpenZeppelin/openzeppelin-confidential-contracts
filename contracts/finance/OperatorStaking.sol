// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626, IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {OperatorRewarder} from "./OperatorRewarder.sol";
import {ProtocolStaking} from "./ProtocolStaking.sol";

contract OperatorStaking is ERC20, Ownable {
    using Math for uint256;
    using Checkpoints for Checkpoints.Trace208;

    ProtocolStaking private immutable _protocolStaking;
    IERC20 private immutable _asset;
    address private _rewarder;
    uint256 private _totalSharesInRedemption;
    mapping(address => uint256) private _sharesReleased;
    mapping(address => Checkpoints.Trace208) private _unstakeRequests;
    mapping(address => mapping(address => bool)) private _operator;

    event OperatorSet(address controller, address operator, bool approved);

    error InsufficientClaimableShares(uint256 requested, uint256 claimable);
    error SameRewarderAlreadySet(address rewarder);

    constructor(
        string memory name,
        string memory symbol,
        ProtocolStaking protocolStaking_,
        address owner
    ) ERC20(name, symbol) Ownable(owner) {
        _asset = IERC20(protocolStaking_.stakingToken());
        _protocolStaking = protocolStaking_;

        IERC20(asset()).approve(address(protocolStaking_), type(uint256).max);

        address rewarder_ = address(new OperatorRewarder(owner, protocolStaking_, this));
        protocolStaking_.setRewardsRecipient(rewarder_);
        _rewarder = rewarder_;
    }

    function asset() public view virtual returns (address) {
        return address(_asset);
    }

    function protocolStaking() public view virtual returns (address) {
        return address(_protocolStaking);
    }

    function rewarder() public view virtual returns (address) {
        return _rewarder;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return super.totalSupply() + totalSharesInRedemption();
    }

    // Can there be reentry such that assets in cooldown and balanceOf are double counted?
    function totalAssets() public view virtual returns (uint256) {
        return
            IERC20(asset()).balanceOf(address(this)) +
            _protocolStaking.balanceOf(address(this)) +
            _protocolStaking.tokensInCooldown(address(this));
    }

    function pendingRedeemRequest(uint256, address controller) public view virtual returns (uint256) {
        return _unstakeRequests[controller].latest() - _unstakeRequests[controller].upperLookup(Time.timestamp());
    }

    function claimableRedeemRequest(uint256, address controller) public view virtual returns (uint256) {
        return _unstakeRequests[controller].upperLookup(Time.timestamp()) - _sharesReleased[controller];
    }

    function totalSharesInRedemption() public view virtual returns (uint256) {
        return _totalSharesInRedemption;
    }

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxRedeem(address owner) public view virtual returns (uint256) {
        return claimableRedeemRequest(0, owner);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    function isOperator(address controller, address operator) public view virtual returns (bool) {
        return _operator[controller][operator];
    }

    function setRewarder(address newRewarder) public virtual onlyOwner {
        address oldRewarder = rewarder();
        require(newRewarder != oldRewarder, SameRewarderAlreadySet(oldRewarder));
        OperatorRewarder(oldRewarder).shutdown();
        _rewarder = newRewarder;
        _protocolStaking.setRewardsRecipient(newRewarder);
    }

    function setOperator(address operator, bool approved) public virtual {
        _operator[msg.sender][operator] = approved;

        emit OperatorSet(msg.sender, operator, approved);
    }

    function deposit(uint256 assets, address receiver) public virtual returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626.ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        return shares;
    }

    function requestRedeem(uint208 shares, address controller, address owner) public virtual {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        uint256 assetsToWithdraw = previewRedeem(shares);
        _burn(owner, shares);
        _protocolStaking.unstake(address(this), assetsToWithdraw);

        (, uint48 lastReleaseTime, uint208 totalSharesRedeemed) = _unstakeRequests[controller].latestCheckpoint();
        uint48 releaseTime = SafeCast.toUint48(
            Math.max(Time.timestamp() + _protocolStaking.unstakeCooldownPeriod(), lastReleaseTime)
        );
        _unstakeRequests[controller].push(releaseTime, totalSharesRedeemed + shares);
        _totalSharesInRedemption += shares;
    }

    function redeem(uint256 shares, address receiver, address controller) public virtual returns (uint256) {
        uint256 maxShares = maxRedeem(controller);

        require(msg.sender == controller || isOperator(controller, msg.sender), "Not authorized");

        if (shares == type(uint256).max) {
            shares = maxShares;
        } else if (shares > maxShares) {
            revert ERC4626.ERC4626ExceededMaxRedeem(controller, shares, maxShares);
        }

        uint256 assets = previewRedeem(shares);
        _totalSharesInRedemption -= shares;
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        emit IERC4626.Withdraw(msg.sender, receiver, controller, shares, assets);

        return assets;
    }

    function restake() public virtual {
        uint256 amountToRestake = IERC20(asset()).balanceOf(address(this)) +
            _protocolStaking.tokensInCooldown(address(this)) -
            previewRedeem(totalSharesInRedemption());
        _protocolStaking.stake(amountToRestake);
    }

    /**
     * @dev Updates shares while notifying the rewarder that shares were transferred.
     * The `from` account should claim unpaid reward before transferring its shares.
     */
    function _update(address from, address to, uint256 amount) internal virtual override {
        OperatorRewarder(rewarder()).transferHook(from, to, amount);
        super._update(from, to, amount);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual {
        // If asset() is ERC-777, `transferFrom` can trigger a reentrancy BEFORE the transfer happens through the
        // `tokensToSend` hook. On the other hand, the `tokenReceived` hook, that is triggered after the transfer,
        // calls the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any reentrancy would happen before the
        // assets are transferred and before the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);
        _mint(receiver, shares);
        _protocolStaking.stake(assets);

        emit IERC4626.Deposit(caller, receiver, assets, shares);
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual returns (uint256) {
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }

    function _decimalsOffset() internal view virtual returns (uint8) {
        return 0;
    }
}
