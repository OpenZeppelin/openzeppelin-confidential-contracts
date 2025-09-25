// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OperatorStakingRewarder} from "./OperatorStakingRewarder.sol";

interface IProtocolStaking {
    function stakingToken() external view returns (address);
    function releasable(address account) external view returns (uint256);
    function setRewardsRecipient(address recipient) external;
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function release() external;
    function claimRewards(address account) external;
}

/**
 * @dev
 */
abstract contract OperatorStaking is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    address private immutable _protocolStaking;
    address private _operatorStakingRewarder;

    error ProtocolStakingTooMuch();
    error ProtocolUnstakingTooMuch();
    error ProtocolNothingReleaseable();

    event ProtocolStaked(uint256 amount);
    event ProtocolUnstaked(uint256 amount);
    event ProtocolReleased();

    constructor(
        address protocolStaking,
        address owner,
        string memory assetName,
        string memory assetSymbol
    ) Ownable(owner) ERC4626(IERC20(IProtocolStaking(protocolStaking).stakingToken())) ERC20(assetName, assetSymbol) {
        _protocolStaking = protocolStaking;
        setRewarder(address(new OperatorStakingRewarder(owner, address(this))));
    }

    /// @dev
    function setRewarder(address rewarder) public virtual onlyOwner {
        IProtocolStaking(_protocolStaking).setRewardsRecipient(rewarder);
    }

    /// @dev
    function protocolStake(uint256 amount) public virtual onlyOwner {
        _protocolStake(amount);
    }

    /// @dev
    function protocolUnstake(uint256 amount) public virtual onlyOwner {
        _protocolUnstake(amount);
    }

    /// @dev
    function protocolRelease() public virtual onlyOwner {
        _protocolRelease();
    }

    /// @dev
    function _protocolStake(uint256 amount) internal virtual {
        IERC20 asset = IERC20(asset());
        require(amount <= asset.balanceOf(address(this)), ProtocolStakingTooMuch());
        asset.approve(_protocolStaking, amount);
        IProtocolStaking(_protocolStaking).stake(amount);
        emit ProtocolStaked(amount);
    }

    /// @dev
    function _protocolUnstake(uint256 amount) internal virtual {
        require(amount <= IERC20(_protocolStaking).balanceOf(address(this)), ProtocolUnstakingTooMuch());
        IProtocolStaking(_protocolStaking).unstake(amount);
        emit ProtocolUnstaked(amount);
    }

    /// @dev
    function _protocolRelease() internal virtual {
        //require(IProtocolStaking(_protocolStaking).releasable(address(this)) > 0, ProtocolNothingReleaseable());
        IProtocolStaking(_protocolStaking).release();
        emit ProtocolReleased();
    }
}
