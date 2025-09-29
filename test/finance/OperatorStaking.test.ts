import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { mine, time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';

const timeIncreaseNoMine = (duration: number) =>
  time.latest().then(clock => time.setNextBlockTimestamp(clock + duration));

describe.only('OperatorStaking', function () {
  beforeEach(async function () {
    const [staker1, staker2, admin, ...accounts] = await ethers.getSigners();

    const token = await ethers.deployContract('$ERC20Mock', ['StakingToken', 'ST', 18]);
    const protocolStaking = await ethers
      .getContractFactory('ProtocolStaking')
      .then(factory => upgrades.deployProxy(factory, ['StakedToken', 'SST', '1', token.target, admin.address]));
    const mock = await ethers.deployContract('$OperatorStaking', ['OPStake', 'OP', protocolStaking]);

    await Promise.all(
      [staker1, staker2].flatMap(account => [
        token.mint(account, ethers.parseEther('1000')),
        token.$_approve(account, mock, ethers.MaxUint256),
      ]),
    );

    Object.assign(this, { staker1, staker2, admin, accounts, token, protocolStaking, mock });
  });

  it('passes on earnings', async function () {
    await this.protocolStaking.connect(this.admin).addEligibleAccount(this.mock);
    await this.protocolStaking.connect(this.admin).setRewardRate(ethers.parseEther('0.5'));

    await this.mock.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);
    await timeIncreaseNoMine(9);

    await this.protocolStaking.claimRewards(this.mock);
    await this.mock.restake();
    await this.mock.connect(this.staker1).redeem(await this.mock.balanceOf(this.staker1), this.staker1, this.staker1);
    expect(await this.token.balanceOf(this.staker1)).to.be.closeTo(ethers.parseEther('1005'), 10n);
    await expect(this.token.balanceOf(this.mock)).to.eventually.be.eq(0);
  });
});
