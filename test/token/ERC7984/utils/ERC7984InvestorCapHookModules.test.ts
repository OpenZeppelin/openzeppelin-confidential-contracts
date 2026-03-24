import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

describe('ERC7984InvestorCapHookModules', function () {
  beforeEach(async function () {
    const [anyone, admin, agent1, holder, recipient, ...others] = await ethers.getSigners();
    const token = (await ethers.deployContract('$ERC7984RwaHookedMock', ['name', 'symbol', 'uri', admin])) as any;
    const complianceModule = await ethers.deployContract('$ERC7984InvestorCapHookModuleMock', [admin]);

    await token
      .connect(admin)
      .installModule(complianceModule, ethers.AbiCoder.defaultAbiCoder().encode(['uint64'], [10]));
    await token.connect(admin).addAgent(agent1);

    await token['$_mint(address,uint64)'](holder, 20000);

    await expect(complianceModule.maxInvestorCount(token)).to.eventually.eq(10);

    Object.assign(this, {
      token,
      complianceModule,
      admin,
      agent1,
      recipient,
      holder,
      anyone,
      others,
    });
  });

  describe('setMaxInvestorCount', function () {
    it('should set the max investor count', async function () {
      await this.complianceModule.connect(this.agent1).setMaxInvestorCount(this.token, 20);
      await expect(this.complianceModule.maxInvestorCount(this.token)).to.eventually.eq(20);
    });

    it('should emit event', async function () {
      await expect(this.complianceModule.connect(this.agent1).setMaxInvestorCount(this.token, 20))
        .to.emit(this.complianceModule, 'MaxInvestorCountSet')
        .withArgs(this.token, 20);
    });

    it.only('should be gated to agent', async function () {
      await expect(this.complianceModule.setMaxInvestorCount(this.token, 20)).to.be.revertedWithCustomError(
        this.complianceModule,
        'Unauthorized',
      );
    });
  });

  describe('_preTransfer', function () {
    it('should allow transfer if new investor count is less than max investor count', async function () {
      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 1000);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.recipient),
      ).to.eventually.equal(1000);
    });

    it('should not allow transfer if new investor count is greater than max investor count', async function () {
      await this.complianceModule.connect(this.agent1).setMaxInvestorCount(this.token, 3);

      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 1000);
      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.others[0], 1000);

      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.anyone, 1000);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.anyone),
      ).to.eventually.equal(0);

      await expect(
        fhevm.userDecryptEuint(
          FhevmType.euint64,
          await this.complianceModule.investorCount(this.token),
          this.complianceModule.target,
          this.admin,
        ),
      ).to.eventually.equal(3);
    });

    it('should allow burning always', async function () {
      await this.complianceModule.connect(this.agent1).setMaxInvestorCount(this.token, 1);

      const tx = await this.token['$_burn(address,uint64)'](this.holder, 1000);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.holder),
      ).to.eventually.equal(1000);
    });

    it('should allow self transfers always', async function () {
      await this.complianceModule.connect(this.agent1).setMaxInvestorCount(this.token, 1);

      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.holder, 1000);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.holder),
      ).to.eventually.equal(1000);
    });

    it('should allow zero transfers always', async function () {
      await this.complianceModule.connect(this.agent1).setMaxInvestorCount(this.token, 1);

      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 0);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.holder),
      ).to.eventually.equal(0);
    });

    it('should require caller has allowance to `fromBalance` and `toBalance`', async function () {});
  });

  describe('_postTransfer', function () {
    it('should increment investor count for a new investor', async function () {
      const beforeInvestorCount = await this.complianceModule.investorCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, beforeInvestorCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(1);

      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 1000);

      const afterInvestorCount = await this.complianceModule.investorCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterInvestorCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(2);
    });

    it('should decrement investor count if investor sends all their balance', async function () {
      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 1000);

      const beforeInvestorCount = await this.complianceModule.investorCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, beforeInvestorCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(2);

      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 19000);

      const afterInvestorCount = await this.complianceModule.investorCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterInvestorCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(1);
    });

    it('should not increment investor count if transfer is zero', async function () {
      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 0);

      const afterInvestorCount = await this.complianceModule.investorCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterInvestorCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(1);
    });

    it('should not increment investor count on burn', async function () {
      await this.token['$_burn(address,uint64)'](this.holder, 1000);

      const afterInvestorCount = await this.complianceModule.investorCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterInvestorCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(1);
    });

    // Note this is a known limitation of the current implementation.
    it('blocks full transfer to new investor when at max investors', async function () {
      await this.complianceModule.connect(this.agent1).setMaxInvestorCount(this.token, 1);

      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 20000);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.recipient),
      ).to.eventually.equal(0);
    });
  });
});
