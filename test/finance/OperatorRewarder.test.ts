import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { mine, time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';

const timeIncreaseNoMine = (duration: number) =>
  time.latest().then(clock => time.setNextBlockTimestamp(clock + duration));

describe.only('OperatorRewarder', function () {
  beforeEach(async function () {
    const [staker1, staker2, admin, ...accounts] = await ethers.getSigners();

    const token = await ethers.deployContract('$ERC20Mock', ['StakingToken', 'ST', 18]);
    const protocolStaking = await ethers
      .getContractFactory('ProtocolStaking')
      .then(factory =>
        upgrades.deployProxy(factory, ['StakedToken', 'SST', '1', token.target, admin.address, 60 /* 1 min */]),
      );
    const operatorStaking = await ethers.deployContract('$OperatorStaking', [
      'OPStake',
      'OP',
      protocolStaking,
      admin.address,
    ]);
    const mock = await ethers.getContractAt('OperatorRewarder', await operatorStaking.rewarder());

    await Promise.all(
      [staker1, staker2].flatMap(account => [
        token.mint(account, ethers.parseEther('1000')),
        token.$_approve(account, operatorStaking, ethers.MaxUint256),
      ]),
    );

    await protocolStaking.connect(admin).addEligibleAccount(operatorStaking);
    await protocolStaking.connect(admin).setRewardRate(ethers.parseEther('0.5'));

    Object.assign(this, { staker1, staker2, admin, accounts, token, operatorStaking, protocolStaking, mock });
  });

  describe('Earned', async function () {
    it('should give all to solo staker', async function () {
      await this.operatorStaking.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);

      await timeIncreaseNoMine(10);
      await this.protocolStaking.connect(this.admin).setRewardRate(ethers.parseEther('0'));

      await expect(this.mock.ownerUnpaidReward()).to.eventually.eq(0);
      await expect(this.mock.unpaidReward()).to.eventually.eq(ethers.parseEther('5'));
      await expect(this.mock.stakerUnpaidReward(this.staker1)).to.eventually.eq(ethers.parseEther('5'));
    });

    it('should split between two equal stakers', async function () {
      await this.operatorStaking.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);
      await this.operatorStaking.connect(this.staker2).deposit(ethers.parseEther('1'), this.staker2);

      await timeIncreaseNoMine(9);
      await this.protocolStaking.connect(this.admin).setRewardRate(0);

      await expect(this.mock.ownerUnpaidReward()).to.eventually.eq(0);
      await expect(this.mock.unpaidReward()).to.eventually.eq(ethers.parseEther('5'));
      await expect(this.mock.stakerUnpaidReward(this.staker2)).to.eventually.eq(ethers.parseEther('2.25'));
      await expect(this.mock.stakerUnpaidReward(this.staker1)).to.eventually.eq(ethers.parseEther('2.75'));
    });

    it('should decrease rewards appropriately for owner fee', async function () {
      await this.mock.connect(this.admin).setOwnerFee('1000'); // 10% owner fee
      await this.operatorStaking.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);

      await time.increase(10);

      await expect(this.mock.stakerUnpaidReward(this.staker1)).to.eventually.eq(ethers.parseEther('4.5'));
      await expect(this.mock.ownerUnpaidReward()).to.eventually.eq(ethers.parseEther('0.5'));
    });
  });

  describe('claimOwnerReward', async function () {
    beforeEach(async function () {
      await this.mock.connect(this.admin).setOwnerFee(1000);
      await this.operatorStaking.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);
    });

    it('should send tokens', async function () {
      await time.increase(20);

      await expect(this.mock.ownerUnpaidReward()).to.eventually.eq(ethers.parseEther('1'));
      await expect(this.mock.stakerUnpaidReward(this.staker1)).to.eventually.eq(ethers.parseEther('9'));

      // 1 more second goes by
      await expect(this.mock.claimOwnerReward())
        .to.emit(this.token, 'Transfer')
        .withArgs(this.mock, this.admin, ethers.parseEther('1.05'));
    });

    it('should reset pending owner fee', async function () {
      await timeIncreaseNoMine(10);
      await this.mock.claimOwnerReward();

      await expect(this.mock.ownerUnpaidReward()).to.eventually.eq(0);
    });

    it('should not effect staker earned amount', async function () {
      await timeIncreaseNoMine(10);
      await this.mock.claimOwnerReward();

      await expect(this.mock.stakerUnpaidReward(this.staker1)).to.eventually.eq(ethers.parseEther('4.5'));
    });

    it('should process second claim accurately', async function () {
      await timeIncreaseNoMine(10);
      await expect(this.mock.claimOwnerReward())
        .to.emit(this.token, 'Transfer')
        .withArgs(this.mock, this.admin, ethers.parseEther('0.5'));

      await timeIncreaseNoMine(5);
      await expect(this.mock.claimOwnerReward())
        .to.emit(this.token, 'Transfer')
        .withArgs(this.mock, this.admin, ethers.parseEther('0.25'));
    });
  });

  describe('setOwnerFee', async function () {
    it('should update storage', async function () {
      await expect(this.mock.ownerFeeBasisPoints()).to.eventually.eq(0);
      await this.mock.connect(this.admin).setOwnerFee(1234);
      await expect(this.mock.ownerFeeBasisPoints()).to.eventually.eq(1234);
    });

    it('should send pending fees', async function () {
      await this.mock.connect(this.admin).setOwnerFee(1000);
      await this.operatorStaking.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);

      await timeIncreaseNoMine(10);
      await expect(this.mock.connect(this.admin).setOwnerFee(2000))
        .to.emit(this.token, 'Transfer')
        .withArgs(this.mock, this.admin, ethers.parseEther('0.5'));
    });

    it('should accrue awards accurately after change', async function () {
      await this.mock.connect(this.admin).setOwnerFee(1000);
      await this.operatorStaking.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);

      await timeIncreaseNoMine(10);
      await this.mock.connect(this.admin).setOwnerFee(2000);

      await time.increase(10);
      await expect(this.mock.stakerUnpaidReward(this.staker1)).to.eventually.eq(ethers.parseEther('8.5'));
      await expect(this.mock.ownerUnpaidReward()).to.eventually.eq(ethers.parseEther('1')); // 0.5 already sent
    });

    it('should not take fees from past rewards', async function () {
      await this.operatorStaking.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);

      await timeIncreaseNoMine(10);
      await this.mock.connect(this.admin).setOwnerFee(1000);
      await expect(this.mock.stakerUnpaidReward(this.staker1)).to.eventually.eq(ethers.parseEther('5'));
      await expect(this.mock.ownerUnpaidReward()).to.eventually.eq(0);

      await time.increase(10);
      await expect(this.mock.stakerUnpaidReward(this.staker1)).to.eventually.eq(ethers.parseEther('9.5'));
      await expect(this.mock.ownerUnpaidReward()).to.eventually.eq(ethers.parseEther('0.5'));
    });
  });

  describe('shutdown', function () {
    beforeEach(async function () {
      await this.operatorStaking.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);
      await timeIncreaseNoMine(10);

      this.tx = this.operatorStaking.connect(this.admin).setRewarder(ethers.ZeroAddress);
    });

    it('should emit event', async function () {
      await expect(this.tx).to.emit(this.mock, 'Shutdown');
    });

    it('should set shutdown flag', async function () {
      await expect(this.mock.isShutdown()).to.eventually.eq(false);
      await this.tx;
      await expect(this.mock.isShutdown()).to.eventually.eq(true);
    });

    it('should stop accruing rewards after shutdown', async function () {
      await this.tx;

      await expect(this.mock.stakerUnpaidReward(this.staker1)).to.eventually.eq(ethers.parseEther('5'));

      await timeIncreaseNoMine(10);
      await expect(this.mock.stakerUnpaidReward(this.staker1)).to.eventually.eq(ethers.parseEther('5'));
    });

    it('only callable by protocolStaking', async function () {
      await expect(this.mock.connect(this.admin).shutdown())
        .to.be.revertedWithCustomError(this.mock, 'CallerNotOperatorStaking')
        .withArgs(this.admin);
    });
  });
});
