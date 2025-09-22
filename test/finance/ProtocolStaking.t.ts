import { FhevmType } from '@fhevm/hardhat-plugin';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { time, mine } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import chai from 'chai';
import { ethers, fhevm } from 'hardhat';

// Extend Chai Assertion interface to include closeToBigInt
declare global {
  namespace Chai {
    interface Assertion {
      closeToLessThanOrEqual(expected: bigint, tolerance: bigint): Assertion;
    }
  }
}

chai.Assertion.addMethod('closeToLessThanOrEqual', function (expected, tolerance) {
  const actual = this._obj;

  new chai.Assertion(actual).to.be.a('bigint');
  new chai.Assertion(expected).to.be.a('bigint');
  new chai.Assertion(tolerance).to.be.a('bigint');

  const diff = actual > expected ? actual - expected : expected - actual;

  this.assert(
    diff <= tolerance && expected >= actual,
    `expected ${actual} to be within ${tolerance} of ${expected}`,
    `expected ${actual} not to be within ${tolerance} of ${expected}`,
    `Difference was ${diff}`,
  );
});

/* eslint-disable no-unexpected-multiline */
describe.only('Protocol Staking', function () {
  beforeEach(async function () {
    const accounts = await ethers.getSigners();
    const [staker1, staker2, admin] = accounts;

    const token = await ethers.deployContract('$ERC20Mock', ['StakingToken', 'ST', 18]);

    const impl = await ethers.deployContract('ProtocolStaking');
    const initializerCall = (await impl.initialize.populateTransaction('StakedToken', 'SST', '1', token.target, admin))
      .data;
    const protocolStaking = await ethers.getContractAt(
      'ProtocolStaking',
      await ethers.deployContract('ERC1967ProxyMock', [impl, initializerCall]),
    );

    this.accounts = accounts.slice(3);
    this.staker1 = staker1;
    this.staker2 = staker2;
    this.admin = admin;
    this.token = token;
    this.mock = protocolStaking;

    for (const account of [staker1, staker2]) {
      await token.mint(account, ethers.parseEther('1000'));
      await this.token.connect(account).approve(this.mock.target, ethers.MaxUint256);
    }
  });

  describe('Staking', function () {
    it('should emit event on stake', async function () {
      await expect(this.mock.connect(this.staker1).stake(ethers.parseEther('100')))
        .to.emit(this.mock, 'TokensStaked')
        .withArgs(this.staker1.address, ethers.parseEther('100'))
        .to.emit(this.token, 'Transfer')
        .withArgs(this.staker1.address, this.mock.target, ethers.parseEther('100'));
      await expect(this.mock.balanceOf(this.staker1)).to.eventually.equal(ethers.parseEther('100'));
    });

    it("should not reward accounts that aren't operators", async function () {
      await this.mock.connect(this.staker1).stake(ethers.parseEther('100'));

      // Reward 0.5 tokens per block in aggregate
      await this.mock.connect(this.admin).setRewardRate(ethers.parseEther('0.5'));
      await mine(10);

      await expect(this.mock.totalStakedWeight()).to.eventually.equal(0);
      await expect(this.mock.connect(this.staker1).earned(this.staker1)).to.eventually.equal(0);
    });

    it('Single user should get 100% of rewards', async function () {
      await this.mock.connect(this.staker1).stake(ethers.parseEther('100'));

      // Reward 0.5 tokens per block in aggregate
      await this.mock.connect(this.admin).setRewardRate(ethers.parseEther('0.5'));
      await this.mock.connect(this.admin).addOperator(this.staker1.address);
      await mine(9);
      await this.mock.connect(this.admin).setRewardRate(0);
      await expect(this.mock.totalStakedWeight()).to.eventually.equal(
        await this.mock.weight(await this.mock.balanceOf(this.staker1)),
      );
      expect(await this.mock.earned(this.staker1)).to.be.closeToLessThanOrEqual(ethers.parseEther('5'), 10n);
    });

    it('Two users should split rewards according to logarithm', async function () {
      await this.mock.connect(this.staker1).stake(ethers.parseEther('100'));
      await this.mock.connect(this.staker2).stake(ethers.parseEther('1000'));

      // Reward 0.5 tokens per block in aggregate
      await this.mock.connect(this.admin).addOperator(this.staker1.address);
      await this.mock.connect(this.admin).addOperator(this.staker2.address);
      await this.mock.connect(this.admin).setRewardRate(ethers.parseEther('0.5'));
      await mine(9);
      await this.mock.connect(this.admin).setRewardRate(0);

      const earned1 = await this.mock.earned(this.staker1);
      const earned2 = await this.mock.earned(this.staker2);

      expect(earned1 + earned2).to.be.closeToLessThanOrEqual(ethers.parseEther('5'), 10n);
      // Should come back to this. Checking that ratio is correct
      expect((earned2 * 1000n) / earned1).to.be.closeToLessThanOrEqual(1050n, 5n);
    });

    it('Second staker should not get reward from previous period', async function () {
      await this.mock.connect(this.admin).addOperator(this.staker1.address);
      await this.mock.connect(this.admin).addOperator(this.staker2.address);

      // Reward 0.5 tokens per block in aggregate
      await this.mock.connect(this.admin).setRewardRate(ethers.parseEther('0.5'));
      // staker1 stakes early and stars accumulating rewards
      await this.mock.connect(this.staker1).stake(ethers.parseEther('100'));
      await mine(9);
      // staker2 stakes late
      await this.mock.connect(this.staker2).stake(ethers.parseEther('100'));
      await mine(9);
      // stop rewards
      await this.mock.connect(this.admin).setRewardRate(0);

      const earned1 = await this.mock.earned(this.staker1);
      const earned2 = await this.mock.earned(this.staker2);

      expect(earned1 + earned2).to.be.closeToLessThanOrEqual(ethers.parseEther('10'), 10n);
      expect(earned1).to.be.closeTo(earned2 * 3n, 5n);
    });
  });

  describe('Unstaking', function () {
    beforeEach(async function () {
      await this.mock.connect(this.staker1).stake(ethers.parseEther('100'));
      await this.mock.connect(this.staker2).stake(ethers.parseEther('1000'));
    });

    it('should transfer instantly if cooldown is 0', async function () {
      const tx = this.mock.connect(this.staker1).unstake(ethers.parseEther('50'));
      await expect(tx).to.changeTokenBalance(this.token, this.staker1, ethers.parseEther('50'));
      await expect(tx).to.changeTokenBalance(this.mock, this.staker1, -ethers.parseEther('50'));
    });

    it('should not transfer if cooldown is set', async function () {
      await this.mock.connect(this.admin).setUnstakeCooldownPeriod(60); // 1 minute
      await expect(this.mock.connect(this.staker1).unstake(ethers.parseEther('50')))
        .to.emit(this.mock, 'Transfer')
        .withArgs(this.staker1.address, ethers.ZeroAddress, ethers.parseEther('50'))
        .to.not.emit(this.token, 'Transfer');
    });

    describe('Release', function () {
      it('should transfer after cooldown complete', async function () {
        await this.mock.connect(this.admin).setUnstakeCooldownPeriod(60); // 1 minute
        await this.mock.connect(this.staker1).unstake(ethers.parseEther('50'));
        await expect(this.mock.tokensInCooldown(this.staker1)).to.eventually.eq(ethers.parseEther('50'));

        await time.setNextBlockTimestamp((await time.latest()) + 60);

        await expect(this.mock.connect(this.staker1).release()).to.changeTokenBalance(
          this.token,
          this.staker1,
          ethers.parseEther('50'),
        );
        await expect(this.mock.tokensInCooldown(this.staker1)).to.eventually.eq(ethers.parseEther('0'));
      });

      it('should only release once', async function () {
        await this.mock.connect(this.admin).setUnstakeCooldownPeriod(60); // 1 minute
        await this.mock.connect(this.staker1).unstake(ethers.parseEther('50'));

        await time.setNextBlockTimestamp((await time.latest()) + 60);

        await expect(this.mock.connect(this.staker1).release()).to.changeTokenBalance(
          this.token,
          this.staker1,
          ethers.parseEther('50'),
        );
        await expect(this.mock.connect(this.staker1).release()).to.not.emit(this.token, 'Transfer');
      });

      it("should not release if cooldown isn't complete", async function () {
        await this.mock.connect(this.admin).setUnstakeCooldownPeriod(60);
        await this.mock.connect(this.staker1).unstake(ethers.parseEther('50'));

        await time.setNextBlockTimestamp((await time.latest()) + 30);
        await expect(this.mock.connect(this.staker1).release()).to.not.emit(this.token, 'Transfer');
      });

      it('should combine multiple complete withdrawals', async function () {
        await this.mock.connect(this.admin).setUnstakeCooldownPeriod(60); // 1 minute
        await this.mock.connect(this.staker1).unstake(ethers.parseEther('50'));

        await time.setNextBlockTimestamp((await time.latest()) + 30);
        await this.mock.connect(this.staker1).unstake(ethers.parseEther('50'));
        await expect(this.mock.tokensInCooldown(this.staker1)).to.eventually.eq(ethers.parseEther('100'));

        await time.setNextBlockTimestamp((await time.latest()) + 60);
        await expect(this.mock.connect(this.staker1).release())
          .to.emit(this.token, 'Transfer')
          .withArgs(this.mock, this.staker1, ethers.parseEther('100'));
        await expect(this.mock.tokensInCooldown(this.staker1)).to.eventually.eq(ethers.parseEther('0'));
      });

      it('should only release completed cooldowns in batch', async function () {
        await this.mock.connect(this.admin).setUnstakeCooldownPeriod(60); // 1 minute
        await this.mock.connect(this.staker1).unstake(ethers.parseEther('25'));

        await time.setNextBlockTimestamp((await time.latest()) + 20);
        await this.mock.connect(this.staker1).unstake(ethers.parseEther('25'));

        await time.setNextBlockTimestamp((await time.latest()) + 20);
        await this.mock.connect(this.staker1).unstake(ethers.parseEther('25'));

        await time.setNextBlockTimestamp((await time.latest()) + 40);
        await expect(this.mock.connect(this.staker1).release())
          .to.emit(this.token, 'Transfer')
          .withArgs(this.mock, this.staker1, ethers.parseEther('50'));
      });

      it('should handle decrease in cooldown period gracefully', async function () {
        await this.mock.connect(this.admin).setUnstakeCooldownPeriod(120);
        await this.mock.connect(this.staker1).unstake(ethers.parseEther('25'));

        await time.setNextBlockTimestamp((await time.latest()) + 30);
        await this.mock.connect(this.admin).setUnstakeCooldownPeriod(30);
        await this.mock.connect(this.staker1).unstake(ethers.parseEther('25'));

        // advance 30 seconds. Still need to wait another 60 seconds for the original unstake request to complete.
        await time.setNextBlockTimestamp((await time.latest()) + 30);
        await expect(this.mock.connect(this.staker1).release()).to.not.emit(this.token, 'Transfer');

        await time.setNextBlockTimestamp((await time.latest()) + 60);
        await expect(this.mock.connect(this.staker1).release())
          .to.emit(this.token, 'Transfer')
          .withArgs(this.mock, this.staker1, ethers.parseEther('50'));
      });
    });

    it('should decrease total staking amount log accordingly', async function () {
      await this.mock.connect(this.admin).addOperator(this.staker1.address);

      const beforetotalStakedWeight = await this.mock.totalStakedWeight();
      const beforeStaker1Log = await this.mock.weight(await this.mock.balanceOf(this.staker1));
      await this.mock.connect(this.staker1).unstake(ethers.parseEther('75'));
      const afterStaker1Log = await this.mock.weight(await this.mock.balanceOf(this.staker1));
      const aftertotalStakedWeight = await this.mock.totalStakedWeight();
      expect(beforetotalStakedWeight - aftertotalStakedWeight).to.equal(beforeStaker1Log - afterStaker1Log);
    });
  });

  describe('Claim Rewards', function () {
    it('should mint from null address', async function () {
      await this.mock.connect(this.staker1).stake(ethers.parseEther('100'));

      // Reward 0.5 tokens per block in aggregate
      await this.mock.connect(this.admin).setRewardRate(ethers.parseEther('0.5'));
      await this.mock.connect(this.admin).addOperator(this.staker1.address);
      await mine(9);
      await this.mock.connect(this.admin).setRewardRate(0);
      const earned = await this.mock.earned(this.staker1);
      await expect(this.mock.claimRewards(this.staker1))
        .to.emit(this.token, 'Transfer')
        .withArgs(ethers.ZeroAddress, this.staker1, earned);
    });

    it('should be able to set recipient', async function () {
      await this.mock.connect(this.staker1).stake(ethers.parseEther('100'));
      await this.mock.connect(this.staker1).setRewardsRecipient(this.staker2);

      await this.mock.connect(this.admin).setRewardRate(ethers.parseEther('0.5'));
      await this.mock.connect(this.admin).addOperator(this.staker1.address);
      await mine(9);

      await expect(this.mock.claimRewards(this.staker1))
        .to.emit(this.token, 'Transfer')
        .withArgs(ethers.ZeroAddress, this.staker2, anyValue);
    });
  });

  describe('Manage Operators', function () {
    describe('Add Operator', function () {
      it('should emit event', async function () {
        await expect(this.mock.connect(this.admin).addOperator(this.staker1.address))
          .to.emit(this.mock, 'OperatorAdded')
          .withArgs(this.staker1.address);
      });

      it('should reflect in operator list', async function () {
        await this.mock.connect(this.admin).addOperator(this.staker1.address);
        await this.mock.connect(this.admin).addOperator(this.staker2.address);

        await expect(this.mock.isOperator(this.staker1.address)).to.eventually.equal(true);
        await expect(this.mock.isOperator(this.staker2.address)).to.eventually.equal(true);
        await expect(this.mock.isOperator(this.admin.address)).to.eventually.equal(false);
      });

      it("can't add twice", async function () {
        await this.mock.connect(this.admin).addOperator(this.staker1.address);
        await expect(this.mock.connect(this.admin).addOperator(this.staker1))
          .to.be.revertedWithCustomError(this.mock, 'OperatorAlreadyExists')
          .withArgs(this.staker1);
      });

      it('should add to totalStakedWeight', async function () {
        const weightBefore = await this.mock.totalStakedWeight();
        const staker1Weight = await this.mock.weight(await this.mock.balanceOf(this.staker1));
        await this.mock.connect(this.admin).addOperator(this.staker1.address);

        await expect(this.mock.totalStakedWeight()).to.eventually.eq(weightBefore + staker1Weight);
      });
    });

    describe('Remove Operator', function () {
      beforeEach(async function () {
        await this.mock.connect(this.admin).addOperator(this.staker1.address);
        await this.mock.connect(this.admin).addOperator(this.staker2.address);
      });

      it('should emit event', async function () {
        await expect(this.mock.connect(this.admin).removeOperator(this.staker1.address))
          .to.emit(this.mock, 'OperatorRemoved')
          .withArgs(this.staker1.address);
      });

      it('should reflect in operator list', async function () {
        await this.mock.connect(this.admin).removeOperator(this.staker1.address);

        await expect(this.mock.isOperator(this.staker1.address)).to.eventually.equal(false);
        await expect(this.mock.isOperator(this.staker2.address)).to.eventually.equal(true);
      });

      it('should revert if not an operator', async function () {
        await expect(this.mock.connect(this.admin).removeOperator(this.admin))
          .to.be.revertedWithCustomError(this.mock, 'OperatorDoesNotExist')
          .withArgs(this.admin);
      });

      it('should deduct from totalStakedWeight', async function () {
        const weightBefore = await this.mock.totalStakedWeight();
        const staker1Weight = await this.mock.weight(await this.mock.balanceOf(this.staker1));
        await this.mock.connect(this.admin).removeOperator(this.staker1.address);

        await expect(this.mock.totalStakedWeight()).to.eventually.eq(weightBefore - staker1Weight);
      });
    });
  });

  describe('Transfer', function () {
    it('transfer is disabled', async function () {
      await this.mock.connect(this.staker1).stake(ethers.parseEther('100'));
      await expect(this.mock.connect(this.staker1).transfer(this.staker2, 100)).to.be.revertedWithCustomError(
        this.mock,
        'TransferDisabled',
      );
    });

    it('transferFrom is disabled', async function () {
      await this.mock.connect(this.staker1).stake(ethers.parseEther('100'));
      await expect(
        this.mock.connect(this.staker1).transferFrom(this.staker1, this.staker2, 100),
      ).to.be.revertedWithCustomError(this.mock, 'TransferDisabled');
    });
  });
});
