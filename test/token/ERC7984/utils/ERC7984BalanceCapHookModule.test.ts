import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

describe('ERC7984BalanceCapHookModule', function () {
  beforeEach(async function () {
    const [anyone, admin, agent1, holder, recipient] = await ethers.getSigners();
    const token = (await ethers.deployContract('$ERC7984RwaHookedMock', ['name', 'symbol', 'uri', admin])) as any;
    const complianceModule = await ethers.deployContract('$ERC7984BalanceCapHookModuleMock');

    await token['$_mint(address,uint64)'](holder, 20000n.toString());

    await token
      .connect(admin)
      .installModule(complianceModule, ethers.AbiCoder.defaultAbiCoder().encode(['uint64'], [10_000]));
    await token.connect(admin).addAgent(agent1);

    await expect(complianceModule.maxBalance(token)).to.eventually.eq(10_000);

    Object.assign(this, {
      token,
      complianceModule,
      admin,
      agent1,
      recipient,
      holder,
      anyone,
    });
  });

  describe('_preTransfer', function () {
    it('should allow transfer if new balance is less than max balance', async function () {
      const beforeBalance = await this.token.confidentialBalanceOf(this.recipient);

      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 1000n);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.recipient),
      ).to.eventually.equal(1000n);

      const afterBalance = await this.token.confidentialBalanceOf(this.recipient);

      expect(beforeBalance).to.equal(0n);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterBalance, this.token.target, this.recipient),
      ).to.eventually.equal(1000n);
    });

    it('should allow transfer if new balance is equal to max balance', async function () {
      const beforeBalance = await this.token.confidentialBalanceOf(this.recipient);

      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 10_000);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.recipient),
      ).to.eventually.equal(10_000n);

      const afterBalance = await this.token.confidentialBalanceOf(this.recipient);
      expect(beforeBalance).to.equal(0n);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterBalance, this.token.target, this.recipient),
      ).to.eventually.equal(10_000n);
    });

    it('should not allow transfer if new balance is greater than max balance', async function () {
      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 10_001);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.recipient),
      ).to.eventually.equal(0n);

      const afterBalance = await this.token.confidentialBalanceOf(this.recipient);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterBalance, this.token.target, this.recipient),
      ).to.eventually.equal(0n);
    });

    it('should allow self transfer always', async function () {
      await this.complianceModule.connect(this.agent1).setMaxBalance(this.token, 900);
      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.holder, 1000);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.holder),
      ).to.eventually.equal(1000n);
    });
  });

  describe('setMaxBalance', function () {
    it('should be gated to agent', async function () {
      await expect(this.complianceModule.setMaxBalance(this.token, 100)).to.be.revertedWithCustomError(
        this.complianceModule,
        'Unauthorized',
      );
    });

    it('should set max balance', async function () {
      await this.complianceModule.connect(this.agent1).setMaxBalance(this.token, 100);
      await expect(this.complianceModule.maxBalance(this.token)).to.eventually.eq(100);
    });

    it('should emit event', async function () {
      await expect(this.complianceModule.connect(this.agent1).setMaxBalance(this.token, 100))
        .to.emit(this.complianceModule, 'MaxBalanceSet')
        .withArgs(this.token, 100);
    });
  });
});
