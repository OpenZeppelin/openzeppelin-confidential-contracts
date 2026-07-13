import { FhevmType } from '@fhevm/hardhat-plugin';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

describe('ERC7984BalanceCapHookModule', function () {
  beforeEach(async function () {
    const [anyone, admin, holder, recipient] = await ethers.getSigners();
    // The token's `isHookManager` (mock) gates module configuration to the owner (`admin`).
    const token = (await ethers.deployContract('$ERC7984HookedMock', ['name', 'symbol', 'uri', admin])) as any;
    const complianceModule = (await ethers.deployContract('$ERC7984BalanceCapHookModuleMock')) as any;

    await token['$_mint(address,uint64)'](holder, 20000n.toString());

    const encryptedInput = await fhevm
      .createEncryptedInput(complianceModule.target, token.target)
      .add64(10_000n)
      .encrypt();

    await token
      .connect(admin)
      .installModule(
        complianceModule,
        ethers.AbiCoder.defaultAbiCoder().encode(
          ['bytes32', 'bytes'],
          [encryptedInput.handles[0], encryptedInput.inputProof],
        ),
      );

    const encryptCap = async (signer: HardhatEthersSigner, value: number | bigint) =>
      fhevm
        .createEncryptedInput(await complianceModule.getAddress(), signer.address)
        .add64(value)
        .encrypt();

    Object.assign(this, {
      token,
      complianceModule,
      admin,
      recipient,
      holder,
      anyone,
      encryptCap,
      initialCap: ethers.hexlify(encryptedInput.handles[0]),
    });
  });

  describe('_onInstall', function () {
    it('should set the initial cap from initData', async function () {
      await expect(this.complianceModule.maxBalance(this.token)).to.eventually.eq(this.initialCap);
    });
  });

  describe('_preTransfer', function () {
    beforeEach(async function () {
      // Seed recipient with 1000 tokens
      await this.token['$_mint(address,uint64)'](this.recipient, 1_000n);
    });

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

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, beforeBalance, this.token.target, this.recipient),
      ).to.eventually.equal(1000n);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterBalance, this.token.target, this.recipient),
      ).to.eventually.equal(2000n);
    });

    it('should allow transfer if new balance is equal to max balance', async function () {
      const beforeBalance = await this.token.confidentialBalanceOf(this.recipient);

      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 9_000);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.recipient),
      ).to.eventually.equal(9_000n);

      const afterBalance = await this.token.confidentialBalanceOf(this.recipient);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, beforeBalance, this.token.target, this.recipient),
      ).to.eventually.equal(1000n);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterBalance, this.token.target, this.recipient),
      ).to.eventually.equal(10_000n);
    });

    it('should not allow transfer if new balance is greater than max balance', async function () {
      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 9_001);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.recipient),
      ).to.eventually.equal(0n);

      const afterBalance = await this.token.confidentialBalanceOf(this.recipient);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterBalance, this.token.target, this.recipient),
      ).to.eventually.equal(1_000n);
    });

    it('should allow self transfer always', async function () {
      const lowerCap = await this.encryptCap(this.admin, 900);
      await this.complianceModule
        .connect(this.admin)
        .setMaxBalance(this.token, lowerCap.handles[0], lowerCap.inputProof);
      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.holder, 1000);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.holder),
      ).to.eventually.equal(1000n);
    });

    it('should allow burning', async function () {
      const tx = await this.token['$_burn(address,uint64)'](this.holder, 1000n);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.holder),
      ).to.eventually.equal(1000n);
    });

    it('should emit ERC7984HookModuleResult on allowed transfer', async function () {
      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 1000n);
      const moduleLog = (await tx.wait()).logs.find((log: any) => log.address == this.complianceModule.target);
      const parsed = this.complianceModule.interface.parseLog(moduleLog);
      expect(parsed.name).to.equal('ERC7984HookModuleResult');
      expect(parsed.args.token).to.equal(this.token.target);
      expect(parsed.args.from).to.equal(this.holder.address);
      expect(parsed.args.to).to.equal(this.recipient.address);
      await expect(
        fhevm.userDecryptEbool(parsed.args.result, this.complianceModule.target, this.holder),
      ).to.eventually.equal(true);
    });

    it('should emit ERC7984HookModuleResult on rejected transfer', async function () {
      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 10_001);
      const moduleLog = (await tx.wait()).logs.find((log: any) => log.address == this.complianceModule.target);
      const parsed = this.complianceModule.interface.parseLog(moduleLog);
      expect(parsed.name).to.equal('ERC7984HookModuleResult');
      expect(parsed.args.from).to.equal(this.holder.address);
      await expect(
        fhevm.userDecryptEbool(parsed.args.result, this.complianceModule.target, this.holder),
      ).to.eventually.equal(false);
    });
  });

  describe('setMaxBalance', function () {
    it('should be gated to the hook manager', async function () {
      const enc = await this.encryptCap(this.anyone, 100);
      await expect(this.complianceModule.connect(this.anyone).setMaxBalance(this.token, enc.handles[0], enc.inputProof))
        .to.be.revertedWithCustomError(this.complianceModule, 'ERC7984HookModuleUnauthorizedHookManager')
        .withArgs(this.anyone);
    });

    it('should set max balance', async function () {
      const enc = await this.encryptCap(this.admin, 100);
      await this.complianceModule.connect(this.admin).setMaxBalance(this.token, enc.handles[0], enc.inputProof);
      await expect(this.complianceModule.maxBalance(this.token)).to.eventually.eq(ethers.hexlify(enc.handles[0]));
    });

    it('should emit event', async function () {
      const enc = await this.encryptCap(this.admin, 100);
      await expect(this.complianceModule.connect(this.admin).setMaxBalance(this.token, enc.handles[0], enc.inputProof))
        .to.emit(this.complianceModule, 'ERC7984BalanceCapHookModuleMaxBalanceSet')
        .withArgs(this.token, ethers.hexlify(enc.handles[0]));
    });
  });
});
