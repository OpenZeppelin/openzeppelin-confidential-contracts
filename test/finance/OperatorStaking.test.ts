import { OperatorStakingRewarder__factory } from '../../types';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { mine, time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';

const timeIncreaseNoMine = (duration: number) =>
  time.latest().then(clock => time.setNextBlockTimestamp(clock + duration));

describe.only('OperatorStaking', function () {
  beforeEach(async function () {
    const [staker1, staker2, admin, operator, anyone, ...accounts] = await ethers.getSigners();

    const token = await ethers.deployContract('$ERC20Mock', ['StakingToken', 'ST', 18]);
    const protocolStaking = await ethers
      .getContractFactory('ProtocolStaking')
      .then(factory => upgrades.deployProxy(factory, ['StakedToken', 'SST', '1', token.target, admin.address]));
    const operatorStaking = await ethers.deployContract(
      '$OperatorStaking',
      ['OPStake', 'OP', protocolStaking],
      operator,
    );
    const operatorStakingRewarder = OperatorStakingRewarder__factory.connect(
      await protocolStaking.rewardsRecipient(operatorStaking.target),
      anyone,
    );

    await Promise.all(
      [staker1, staker2].flatMap(account => [
        token.mint(account, ethers.parseEther('1000')),
        token.$_approve(account, operatorStaking, ethers.MaxUint256),
      ]),
    );

    Object.assign(this, {
      staker1,
      staker2,
      admin,
      operator,
      anyone,
      accounts,
      token,
      protocolStaking,
      operatorStaking,
      operatorStakingRewarder,
    });
  });

  it('passes on earnings (operator, staker1 & staker2)', async function () {
    await this.protocolStaking.connect(this.admin).addEligibleAccount(this.operatorStaking);
    await this.protocolStaking.connect(this.admin).setRewardRate(ethers.parseEther('0.5'));
    await this.operatorStaking.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);
    await this.operatorStaking.connect(this.staker2).deposit(ethers.parseEther('1'), this.staker2);
    await mine(1);
    await this.protocolStaking.connect(this.admin).setRewardRate(0); // stop rewarding for easier accounting
    const earned: bigint = await this.protocolStaking.earned(this.operatorStaking.target);
    expect(earned).greaterThan(0);
    await this.protocolStaking.claimRewards(this.operatorStaking.target);
    await expect(this.token.balanceOf(this.operatorStaking.target)).to.eventually.equal(0);
    await expect(this.token.balanceOf(this.operatorStakingRewarder.target)).to.eventually.equal(earned);
    await this.operatorStakingRewarder.withdrawRewards(this.operator.address);
    const expectedOperatorReward = (earned * (await this.operatorStakingRewarder.operatorRewardRatio())) / 100n;
    const expectedHoldersReward = earned - expectedOperatorReward;
    const holdersLength = 2;
    const expectedHolderReward = expectedHoldersReward / BigInt(holdersLength);
    await expect(this.token.balanceOf(this.operator.address)).to.eventually.equal(expectedOperatorReward);
    await expect(this.token.balanceOf(this.operatorStakingRewarder.target)).to.eventually.equal(expectedHoldersReward);
    // holder1 claim
    const staker1BalanceBefore = await this.token.balanceOf(this.staker1.address);
    await this.operatorStakingRewarder.withdrawRewards(this.staker1.address);
    const staker1BalanceAfter = await this.token.balanceOf(this.staker1.address);
    expect(staker1BalanceAfter - staker1BalanceBefore).to.equal(expectedHolderReward);
    // holder2 claim
    const staker2BalanceBefore = await this.token.balanceOf(this.staker2.address);
    await this.operatorStakingRewarder.withdrawRewards(this.staker2.address);
    const staker2BalanceAfter = await this.token.balanceOf(this.staker2.address);
    expect(staker2BalanceAfter - staker2BalanceBefore).to.equal(expectedHolderReward);
    await expect(this.token.balanceOf(this.operatorStakingRewarder.target)).to.eventually.equal(0);
  });
});
