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
      .then(factory =>
        upgrades.deployProxy(factory, ['StakedToken', 'SST', '1', token.target, admin.address, 60 /* 1 min */]),
      );
    const mock = await ethers.deployContract('$OperatorStaking', ['OPStake', 'OP', protocolStaking, admin.address]);

    await Promise.all(
      [staker1, staker2].flatMap(account => [
        token.mint(account, ethers.parseEther('1000')),
        token.$_approve(account, mock, ethers.MaxUint256),
      ]),
    );

    Object.assign(this, { staker1, staker2, admin, accounts, token, protocolStaking, mock });
  });

  it('simple withdrawal', async function () {
    await this.mock.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);
    await this.mock
      .connect(this.staker1)
      .requestRedeem(await this.mock.balanceOf(this.staker1), this.staker1, this.staker1);

    await timeIncreaseNoMine(60);
    await this.protocolStaking.release(this.mock);
    await this.mock.connect(this.staker1).redeem(ethers.MaxUint256, this.staker1, this.staker1);
    expect(await this.token.balanceOf(this.staker1)).to.be.eq(ethers.parseEther('1000'));
    await expect(this.token.balanceOf(this.mock)).to.eventually.be.eq(0);
  });

  it('symmetrically passes on losses from staked balance without pending withdrawal', async function () {
    await this.mock.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);
    await this.mock.connect(this.staker2).deposit(ethers.parseEther('2'), this.staker2);

    await this.protocolStaking.slash(this.mock, ethers.parseEther('1.5'));

    // Request redemption of all shares and verify actual withdrawal amounts
    await this.mock
      .connect(this.staker1)
      .requestRedeem(await this.mock.balanceOf(this.staker1), this.staker1, this.staker1);
    await this.mock
      .connect(this.staker2)
      .requestRedeem(await this.mock.balanceOf(this.staker2), this.staker2, this.staker2);

    await timeIncreaseNoMine(60);
    await this.protocolStaking.release(this.mock);

    await expect(
      this.mock.connect(this.staker1).redeem(ethers.MaxUint256, this.staker1, this.staker1),
    ).to.changeTokenBalance(this.token, this.staker1, ethers.parseEther('0.5'));
    await expect(
      this.mock.connect(this.staker2).redeem(ethers.MaxUint256, this.staker2, this.staker2),
    ).to.changeTokenBalance(this.token, this.staker2, ethers.parseEther('1'));
  });

  it('symmetrically passes on losses from staked balance with pending withdrawal', async function () {
    await this.mock.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);
    await this.mock.connect(this.staker2).deposit(ethers.parseEther('2'), this.staker2);

    await this.mock.connect(this.staker1).requestRedeem(ethers.parseEther('0.5'), this.staker1, this.staker1);
    // 50% slashing
    await this.protocolStaking.slash(this.mock, ethers.parseEther('1.5'));

    await timeIncreaseNoMine(60);
    await this.protocolStaking.release(this.mock);

    await expect(
      this.mock.connect(this.staker1).redeem(ethers.MaxUint256, this.staker1, this.staker1),
    ).to.changeTokenBalance(this.token, this.staker1, ethers.parseEther('0.25'));
  });

  it('restake excess raw assets after slashing', async function () {
    await this.mock.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);
    await this.mock.connect(this.staker2).deposit(ethers.parseEther('2'), this.staker2);

    await this.mock.connect(this.staker1).requestRedeem(ethers.parseEther('1'), this.staker1, this.staker1);
    await this.protocolStaking.slash(this.mock, ethers.parseEther('1.5'));

    await timeIncreaseNoMine(60);
    await this.protocolStaking.release(this.mock);
    await expect(this.mock.connect(this.staker2).requestRedeem(ethers.parseEther('2'), this.staker2, this.staker2))
      .reverted;

    await this.mock.restake();
    this.mock.connect(this.staker2).requestRedeem(ethers.parseEther('2'), this.staker2, this.staker2);
  });

  it('symmetrically passes on losses from withdrawal balance', async function () {
    await this.mock.connect(this.staker1).deposit(ethers.parseEther('1'), this.staker1);
    await this.mock.connect(this.staker2).deposit(ethers.parseEther('2'), this.staker2);

    await this.mock.connect(this.staker1).requestRedeem(ethers.parseEther('1'), this.staker1, this.staker1);
    await this.mock.connect(this.staker2).requestRedeem(ethers.parseEther('2'), this.staker2, this.staker2);

    await this.protocolStaking.slashWithdrawal(this.mock, ethers.parseEther('1.5'));

    await timeIncreaseNoMine(60);

    await this.protocolStaking.release(this.mock);
    await expect(
      this.mock.connect(this.staker1).redeem(ethers.MaxUint256, this.staker1, this.staker1),
    ).to.changeTokenBalance(this.token, this.staker1, ethers.parseEther('0.5'));
    await expect(
      this.mock.connect(this.staker2).redeem(ethers.MaxUint256, this.staker2, this.staker2),
    ).to.changeTokenBalance(this.token, this.staker2, ethers.parseEther('1'));
  });
});
