import { OperatorStaking, OperatorStakingRewarder__factory } from '../../types';
import { $ERC20Mock } from '../../types/contracts-exposed/mocks/token/ERC20Mock.sol/$ERC20Mock';
import { mine } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';

async function fixture() {
  const [baseTokenOwner, protocolAdmin, operator, holder1, holder2, anyone] = await ethers.getSigners();
  const baseToken = (await ethers.deployContract(
    '$ERC20Mock',
    ['BaseStakingToken', 'BST', 18],
    baseTokenOwner,
  )) as any as $ERC20Mock;
  const protocolStaking = await ethers
    .getContractFactory('ProtocolStaking')
    .then(factory =>
      upgrades.deployProxy(factory, ['ProtocolStakingToken', 'PST', '1', baseToken.target, protocolAdmin.address]),
    );
  const operatorStaking = (await ethers.deployContract(
    '$OperatorStaking',
    [protocolStaking.target, operator, 'OperatorStakingToken', 'OST'],
    operator,
  )) as any as OperatorStaking;
  const operatorStakingRewarder = OperatorStakingRewarder__factory.connect(
    await protocolStaking.rewardsRecipient(operatorStaking.target),
    anyone,
  );
  await protocolStaking.connect(protocolAdmin).setRewardRate(ethers.parseEther('0.5'));
  await protocolStaking.connect(protocolAdmin).addOperator(operatorStaking.target);
  return {
    baseTokenOwner,
    baseToken,
    protocolAdmin,
    protocolStaking,
    operator,
    operatorStaking,
    operatorStakingRewarder,
    holder1,
    holder2,
    anyone,
  };
}

describe.only('Operator Staking', function () {
  describe('Staking config', function () {
    it('should set rewarder', async function () {
      const { protocolStaking, operator, operatorStaking } = await fixture();
      const newRewarder = '0x0000000000000000000000000000000000000001';
      await operatorStaking.connect(operator).setRewarder(newRewarder);
      await expect(protocolStaking.rewardsRecipient(operatorStaking.target)).to.eventually.equal(newRewarder);
    });
  });

  describe('Rewarder config', function () {
    it('should get staking token', async function () {
      const { baseToken, operatorStakingRewarder } = await fixture();
      await expect(operatorStakingRewarder.stakingToken()).to.eventually.equal(baseToken.target);
    });

    it('should set rewarder ratios', async function () {
      const { operator, operatorStakingRewarder } = await fixture();
      await operatorStakingRewarder.connect(operator).setHoldersRewardRatio(90);
      await expect(operatorStakingRewarder.holdersRewardRatio()).to.eventually.equal(90);
      await expect(operatorStakingRewarder.operatorRewardRatio()).to.eventually.equal(10);
    });
  });

  describe('Holder staking and unstaking', function () {
    it('should claim holder rewards if operator staked', async function () {
      const {
        baseToken,
        protocolAdmin,
        protocolStaking,
        operator,
        operatorStaking,
        operatorStakingRewarder,
        holder1,
        holder2,
      } = await fixture();
      const amount = 100;
      const holders = [holder1, holder2];
      for (const holder of holders) {
        await baseToken.$_mint(holder.address, amount);
        await baseToken.connect(holder).approve(operatorStaking.target, amount);
        await operatorStaking.connect(holder).deposit(amount, holder.address);
      }
      await operatorStaking.connect(operator).protocolStake(amount * holders.length);
      await mine(1);
      await protocolStaking.connect(protocolAdmin).setRewardRate(0); // stop rewarding for easier accounting
      const earned = await protocolStaking.earned(operatorStaking.target);
      expect(earned).greaterThan(0);
      await protocolStaking.claimRewards(operatorStaking.target);
      await expect(baseToken.balanceOf(operatorStaking.target)).to.eventually.equal(0);
      await expect(baseToken.balanceOf(operatorStakingRewarder.target)).to.eventually.equal(earned);
      await operatorStakingRewarder.claim(operator.address);
      const expectedOperatorReward = earned / 2n;
      const expectedHoldersReward = earned - expectedOperatorReward;
      const expectedHolderReward = expectedHoldersReward / 2n;
      await expect(baseToken.balanceOf(operator.address)).to.eventually.equal(expectedOperatorReward);
      await expect(baseToken.balanceOf(operatorStakingRewarder.target)).to.eventually.equal(expectedHoldersReward);
      await operatorStakingRewarder.claim(holder1.address);
      await expect(baseToken.balanceOf(holder1.address)).to.eventually.equal(expectedHolderReward);
      await expect(baseToken.balanceOf(operatorStakingRewarder.target)).to.eventually.equal(expectedHolderReward);
      await operatorStakingRewarder.claim(holder2.address);
      await expect(baseToken.balanceOf(holder2.address)).to.eventually.equal(expectedHolderReward);
      await expect(baseToken.balanceOf(operatorStakingRewarder.target)).to.eventually.equal(0);
    });

    it('should get holder stake if operator unstaked and released', async function () {
      const { baseToken, operator, operatorStaking, holder1, holder2 } = await fixture();
      const amount = 100;
      const holders = [holder1, holder2];
      for (const holder of holders) {
        await baseToken.$_mint(holder.address, amount);
        await baseToken.connect(holder).approve(operatorStaking.target, amount);
        await operatorStaking.connect(holder).deposit(amount, holder.address);
        await expect(baseToken.balanceOf(holder.address)).to.eventually.equal(0);
      }
      await expect(baseToken.balanceOf(operatorStaking.target)).to.eventually.equal(amount * holders.length);
      await operatorStaking.connect(operator).protocolStake(amount * holders.length);
      await operatorStaking.connect(operator).protocolUnstake(amount * holders.length);
      await operatorStaking.connect(operator).protocolRelease();
      for (const holder of holders) {
        await operatorStaking.connect(holder).withdraw(amount, holder.address, holder.address);
        await expect(baseToken.balanceOf(holder.address)).to.eventually.equal(amount);
      }
      await expect(baseToken.balanceOf(operatorStaking.target)).to.eventually.equal(0);
    });
  });
});
