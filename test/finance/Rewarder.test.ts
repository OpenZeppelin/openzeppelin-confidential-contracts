import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { mine, time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';

const timeIncreaseNoMine = (duration: number) =>
  time.latest().then(clock => time.setNextBlockTimestamp(clock + duration));

describe.only('Rewarder', function () {
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
    const mock = await ethers.getContractAt('Rewarder', await operatorStaking.rewarder());

    await Promise.all(
      [staker1, staker2].flatMap(account => [
        token.mint(account, ethers.parseEther('1000')),
        token.$_approve(account, operatorStaking, ethers.MaxUint256),
      ]),
    );

    await protocolStaking.connect(admin).addEligibleAccount(operatorStaking);

    Object.assign(this, { staker1, staker2, admin, accounts, token, operatorStaking, protocolStaking, mock });
  });

  describe('Earned', async function () {
    it('should give all to solo staker', async function () {
      await this.operatorStaking.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);
      await this.protocolStaking.connect(this.admin).setRewardRate(ethers.parseEther('0.5'));

      await timeIncreaseNoMine(10);
      await this.protocolStaking.connect(this.admin).setRewardRate(ethers.parseEther('0'));

      await expect(this.mock.pendingOwnerFee()).to.eventually.eq(0);
      await expect(this.mock.earned(this.staker1)).to.eventually.eq(ethers.parseEther('5'));
      await expect(this.mock.unpaidRewards(this.staker1)).to.eventually.eq(ethers.parseEther('5'));

      await expect(this.mock.claimRewards(this.staker1)).to.changeTokenBalance(
        this.token,
        this.staker1,
        ethers.parseEther('5'),
      );
    });
  });
});
