import { OperatorStaking } from '../../types';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';

const timeIncreaseNoMine = (duration: number) =>
  time.latest().then(clock => time.setNextBlockTimestamp(clock + duration));

describe('OperatorStaking', function () {
  beforeEach(async function () {
    const [staker1, staker2, staker3, admin, operator, anyone, ...accounts] = await ethers.getSigners();

    const token = await ethers.deployContract('$ERC20Mock', ['StakingToken', 'ST', 18]);
    const protocolStaking = await ethers
      .getContractFactory('ProtocolStaking')
      .then(factory => upgrades.deployProxy(factory, ['StakedToken', 'SST', '1', token.target, admin.address]));
    const operatorStaking = (await ethers.deployContract(
      '$OperatorStaking',
      ['OPStake', 'OP', protocolStaking, operator],
      operator,
    )) as any as OperatorStaking;
    const stakersRewardsRecipient = await ethers.deployContract(
      'StakersRewardsRecipient',
      [operator, operatorStaking.target],
      operator,
    );
    const globalRewardsRecipient = await ethers.deployContract(
      'PaymentSplitter',
      [
        [operator.address, stakersRewardsRecipient.target],
        [50, 50],
      ],
      operator,
    );

    await operatorStaking.connect(operator).setGlobalRewardsRecipient(globalRewardsRecipient);
    await operatorStaking.connect(operator).setStakersRewardsRecipient(stakersRewardsRecipient);

    await Promise.all(
      [staker1, staker2, staker3].flatMap(account => [
        token.mint(account, ethers.parseEther('1000')),
        token.$_approve(account, operatorStaking, ethers.MaxUint256),
      ]),
    );

    Object.assign(this, {
      staker1,
      staker2,
      staker3,
      admin,
      operator,
      anyone,
      accounts,
      token,
      protocolStaking,
      operatorStaking,
      globalRewardsRecipient,
      stakersRewardsRecipient,
    });
  });

  it('Deposit and withdraw rewards (operator & 3 stakers)', async function () {
    const globalRewardsPerSec = ethers.parseEther('0.5');
    const stakersRewardPerSec = (globalRewardsPerSec * 50n) / 100n; // 50% to stakers, other 50% to operator
    const operatorRewardPerSec = globalRewardsPerSec - stakersRewardPerSec;
    await this.protocolStaking.connect(this.admin).addEligibleAccount(this.operatorStaking);
    await this.operatorStaking.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);
    await this.protocolStaking.connect(this.admin).setRewardRate(globalRewardsPerSec); // only start rewarding after staker1 deposit
    await this.operatorStaking.connect(this.staker2).deposit(ethers.parseEther('1'), this.staker2);
    await this.operatorStaking.connect(this.staker3).deposit(ethers.parseEther('1'), this.staker3);
    await this.protocolStaking.connect(this.admin).setRewardRate(0); // stop rewarding for easier accounting
    const stakerRewards1 = stakersRewardPerSec / 1n; // 1st second reward
    const stakerRewards2 = stakersRewardPerSec / 2n; // 2nd second reward
    const stakerRewards3 = stakersRewardPerSec / 3n; // 3rd second reward
    const operatorBalanceBefore = await this.token.balanceOf(this.operator.address);
    const staker1BalanceBefore = await this.token.balanceOf(this.staker1.address);
    const staker2BalanceBefore = await this.token.balanceOf(this.staker2.address);
    const staker3BalanceBefore = await this.token.balanceOf(this.staker3.address);
    await this.operatorStaking.withdrawRewards(this.operator.address);
    await this.operatorStaking.withdrawRewards(this.staker1.address);
    await this.operatorStaking.withdrawRewards(this.staker2.address);
    await this.operatorStaking.withdrawRewards(this.staker3.address);
    const operatorBalanceAfter = await this.token.balanceOf(this.operator.address);
    const staker1BalanceAfter = await this.token.balanceOf(this.staker1.address);
    const staker2BalanceAfter = await this.token.balanceOf(this.staker2.address);
    const staker3BalanceAfter = await this.token.balanceOf(this.staker3.address);
    expect(operatorBalanceAfter - operatorBalanceBefore).to.equal(operatorRewardPerSec * 3n);
    expect(staker1BalanceAfter - staker1BalanceBefore).to.equal(stakerRewards1 + stakerRewards2 + stakerRewards3);
    expect(staker2BalanceAfter - staker2BalanceBefore).to.equal(stakerRewards2 + stakerRewards3);
    expect(staker3BalanceAfter - staker3BalanceBefore).to.equal(stakerRewards3);
  });

  it('Deposit and withdraw stake (operator & 3 stakers)', async function () {
    const globalRewardsPerSec = ethers.parseEther('0.5');
    const stakersRewardPerSec = (globalRewardsPerSec * 50n) / 100n; // 50% to stakers, other 50% to operator
    await this.protocolStaking.connect(this.admin).addEligibleAccount(this.operatorStaking);
    const deposit = ethers.parseEther('1');
    await this.operatorStaking.connect(this.staker1).deposit(deposit, this.staker1);
    await this.protocolStaking.connect(this.admin).setRewardRate(globalRewardsPerSec); // only start rewarding after staker1 deposit
    await this.operatorStaking.connect(this.staker2).deposit(deposit, this.staker2);
    await this.operatorStaking.connect(this.staker3).deposit(deposit, this.staker3);
    await this.protocolStaking.connect(this.admin).setRewardRate(0); // stop rewarding for easier accounting
    const stakerRewards1 = stakersRewardPerSec / 1n; // 1st second reward
    const stakerRewards2 = stakersRewardPerSec / 2n; // 2nd second reward
    const stakerRewards3 = stakersRewardPerSec / 3n; // 3rd second reward
    const staker1BalanceBefore = await this.token.balanceOf(this.staker1.address);
    const staker2BalanceBefore = await this.token.balanceOf(this.staker2.address);
    const staker3BalanceBefore = await this.token.balanceOf(this.staker3.address);
    await this.operatorStaking.connect(this.staker1).redeem(deposit, this.staker1.address, this.staker1.address);
    await this.operatorStaking.connect(this.staker2).redeem(deposit, this.staker2.address, this.staker2.address);
    await this.operatorStaking.connect(this.staker3).redeem(deposit, this.staker3.address, this.staker3.address);
    const staker1BalanceAfter = await this.token.balanceOf(this.staker1.address);
    const staker2BalanceAfter = await this.token.balanceOf(this.staker2.address);
    const staker3BalanceAfter = await this.token.balanceOf(this.staker3.address);
    // Each staker should get back their deposit and their rewards
    expect(staker1BalanceAfter - staker1BalanceBefore).to.equal(
      deposit + stakerRewards1 + stakerRewards2 + stakerRewards3,
    );
    expect(staker2BalanceAfter - staker2BalanceBefore).to.equal(deposit + stakerRewards2 + stakerRewards3);
    expect(staker3BalanceAfter - staker3BalanceBefore).to.closeTo(deposit + stakerRewards3, 1);
  });

  it('Restake rewards', async function () {
    const globalRewardsPerSec = ethers.parseEther('0.5');
    const stakersRewardPerSec = (globalRewardsPerSec * 50n) / 100n; // 50% to stakers, other 50% to operator
    await this.protocolStaking.connect(this.admin).addEligibleAccount(this.operatorStaking);
    const deposit = ethers.parseEther('1');
    await this.operatorStaking.connect(this.staker1).deposit(deposit, this.staker1);
    await this.protocolStaking.connect(this.admin).setRewardRate(globalRewardsPerSec); // only start rewarding after staker1 deposit
    await this.protocolStaking.connect(this.admin).setRewardRate(0); // stop rewarding for easier accounting
    const stakerRewards1 = stakersRewardPerSec / 1n; // 1st second reward
    const stakerSharesBefore = await this.operatorStaking.balanceOf(this.staker1.address);
    await this.operatorStaking.connect(this.staker1).restakeRewards();
    const stakerSharesAfter = await this.operatorStaking.balanceOf(this.staker1.address);
    expect(stakerSharesAfter - stakerSharesBefore).to.equal(stakerRewards1);
  });
});
