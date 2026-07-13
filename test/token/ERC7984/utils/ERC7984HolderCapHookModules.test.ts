import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

describe('ERC7984HolderCapHookModules', function () {
  beforeEach(async function () {
    const [anyone, admin, holder, recipient, ...others] = await ethers.getSigners();
    // The token's `isHookManager` (mock) gates module configuration to the owner (`admin`).
    const token = (await ethers.deployContract('$ERC7984HookedMock', ['name', 'symbol', 'uri', admin])) as any;
    const complianceModule = await ethers.deployContract('$ERC7984HolderCapHookModuleMock', [admin]);

    await token
      .connect(admin)
      .installModule(complianceModule, ethers.AbiCoder.defaultAbiCoder().encode(['uint64'], [10]));

    await token['$_mint(address,uint64)'](holder, 20000);

    await expect(complianceModule.maxHolderCount(token)).to.eventually.eq(10);

    Object.assign(this, {
      token,
      complianceModule,
      admin,
      recipient,
      holder,
      anyone,
      others,
    });
  });

  describe('setMaxHolderCount', function () {
    it('should set the max holder count', async function () {
      await this.complianceModule.connect(this.admin).setMaxHolderCount(this.token, 20);
      await expect(this.complianceModule.maxHolderCount(this.token)).to.eventually.eq(20);
    });

    it('should emit event', async function () {
      await expect(this.complianceModule.connect(this.admin).setMaxHolderCount(this.token, 20))
        .to.emit(this.complianceModule, 'ERC7984HolderCapHookModuleMaxHolderCountSet')
        .withArgs(this.token, 20);
    });

    it('should be gated to the hook manager', async function () {
      await expect(this.complianceModule.connect(this.anyone).setMaxHolderCount(this.token, 20))
        .to.be.revertedWithCustomError(this.complianceModule, 'ERC7984HookModuleUnauthorizedHookManager')
        .withArgs(this.anyone);
    });
  });

  describe('_preTransfer', function () {
    it('should allow transfer if new holder count is less than max holder count', async function () {
      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 1000);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.recipient),
      ).to.eventually.equal(1000);
    });

    it('should not allow transfer if new holder count is greater than max holder count', async function () {
      await this.complianceModule.connect(this.admin).setMaxHolderCount(this.token, 3);

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
          await this.complianceModule.holderCount(this.token),
          this.complianceModule.target,
          this.admin,
        ),
      ).to.eventually.equal(3);
    });

    it('should not increment holder count if recipient is already a holder', async function () {
      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 1000);

      const beforeHolderCount = await this.complianceModule.holderCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, beforeHolderCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(2);

      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 1000);

      const afterHolderCount = await this.complianceModule.holderCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterHolderCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(2);
    });

    it('should allow burning always', async function () {
      await this.complianceModule.connect(this.admin).setMaxHolderCount(this.token, 1);

      const tx = await this.token['$_burn(address,uint64)'](this.holder, 1000);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.holder),
      ).to.eventually.equal(1000);
    });

    it('should allow self transfers always', async function () {
      await this.complianceModule.connect(this.admin).setMaxHolderCount(this.token, 1);

      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.holder, 1000);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.holder),
      ).to.eventually.equal(1000);
    });

    it('should allow zero transfers always', async function () {
      await this.complianceModule.connect(this.admin).setMaxHolderCount(this.token, 1);

      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 0);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.holder),
      ).to.eventually.equal(0);
    });

    it('should revert if `fromBalance` is not allowed to the caller', async function () {
      const maliciousCaller = await ethers.deployContract('ERC7984MaliciousHookCallerMock');

      // holderCount is a real, initialized handle the compliance module owns — but the
      // malicious caller has no FHE allowance for it, triggering the isAllowed guard.
      const holderCountHandle = await this.complianceModule.holderCount(this.token);
      await maliciousCaller.setConfidentialBalance(this.holder.address, holderCountHandle);

      await expect(
        maliciousCaller.callPreTransfer(this.complianceModule, this.holder.address, this.recipient.address, 1),
      )
        .to.be.revertedWithCustomError(this.complianceModule, 'ERC7984HookModuleUnauthorizedUseOfEncryptedAmount')
        .withArgs(holderCountHandle, maliciousCaller);
    });

    it('should revert if `toBalance` is not allowed to the caller', async function () {
      const maliciousCaller = await ethers.deployContract('ERC7984MaliciousHookCallerMock');

      // Give `from` a real owned balance (>= transfer amount) so its check passes
      await maliciousCaller.setConfidentialBalanceWithAllowance(this.holder.address, 1000);

      const holderCountHandle = await this.complianceModule.holderCount(this.token);
      await maliciousCaller.setConfidentialBalance(this.recipient.address, holderCountHandle);

      await expect(
        maliciousCaller.callPreTransfer(this.complianceModule, this.holder.address, this.recipient.address, 1),
      )
        .to.be.revertedWithCustomError(this.complianceModule, 'ERC7984HookModuleUnauthorizedUseOfEncryptedAmount')
        .withArgs(holderCountHandle, maliciousCaller);
    });

    it('should be allowed to transfer to an existing holder at cap', async function () {
      await this.complianceModule.connect(this.admin).setMaxHolderCount(this.token, 3);

      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 1000);
      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.others[0], 1000);

      const beforeHolderCount = await this.complianceModule.holderCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, beforeHolderCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(3);

      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 1000);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.recipient),
      ).to.eventually.equal(1000);

      const afterHolderCount = await this.complianceModule.holderCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterHolderCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(3);
    });
  });

  describe('_postTransfer', function () {
    it('should increment holder count for a new holder', async function () {
      const beforeHolderCount = await this.complianceModule.holderCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, beforeHolderCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(1);

      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 1000);

      const afterHolderCount = await this.complianceModule.holderCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterHolderCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(2);
    });

    it('should decrement holder count if holder sends all their balance', async function () {
      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 1000);

      const beforeHolderCount = await this.complianceModule.holderCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, beforeHolderCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(2);

      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 19000);

      const afterHolderCount = await this.complianceModule.holderCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterHolderCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(1);
    });

    it('should not increment holder count if transfer is zero', async function () {
      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 0);

      const afterHolderCount = await this.complianceModule.holderCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterHolderCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(1);
    });

    it('should not increment holder count on burn', async function () {
      await this.token['$_burn(address,uint64)'](this.holder, 1000);

      const afterHolderCount = await this.complianceModule.holderCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterHolderCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(1);
    });

    it('allows full transfer to new holder when at max holders', async function () {
      await this.complianceModule.connect(this.admin).setMaxHolderCount(this.token, 1);

      const tx = await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 20000);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.recipient),
      ).to.eventually.equal(20000);
    });

    it('blocks full transfer to new holder when above max holders', async function () {
      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 1000);
      await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.others[0], 1000);

      const beforeHolderCount = await this.complianceModule.holderCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, beforeHolderCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(3);

      await this.complianceModule.connect(this.admin).setMaxHolderCount(this.token, 2);

      const tx = await this.token.connect(this.recipient)['confidentialTransfer(address,uint64)'](this.anyone, 1000);
      const transferEvent = await tx.wait().then((res: any) => {
        return res.logs.filter((log: any) => log.address == this.token.target)[0];
      });

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], this.token.target, this.anyone),
      ).to.eventually.equal(0);

      const afterHolderCount = await this.complianceModule.holderCount(this.token);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterHolderCount, this.complianceModule.target, this.admin),
      ).to.eventually.equal(3);
    });
  });
});
