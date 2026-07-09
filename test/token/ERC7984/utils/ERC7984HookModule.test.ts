import { INTERFACE_IDS, INVALID_ID } from '../../../helpers/interface';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

describe('ERC7984HookModule', function () {
  beforeEach(async function () {
    const [admin, holder, recipient, anyone] = await ethers.getSigners();
    const hookModule = await ethers.deployContract('$ERC7984HookModuleMock');

    Object.assign(this, {
      hookModule,
      admin,
      holder,
      recipient,
      anyone,
    });
  });

  describe('ERC165', function () {
    it('should support interface', async function () {
      await expect(this.hookModule.supportsInterface(INTERFACE_IDS.ERC7984HookModule)).to.eventually.be.true;
    });

    it('should not support interface', async function () {
      await expect(this.hookModule.supportsInterface(INVALID_ID)).to.eventually.be.false;
    });
  });

  describe('preTransfer', function () {
    it('should revert if the caller does not have access to the encrypted amount', async function () {
      const encryptedAmount = await fhevm
        .createEncryptedInput(this.hookModule.target, this.holder.address)
        .add64(100)
        .encrypt();

      await expect(
        this.hookModule.preTransfer(this.holder.address, this.recipient.address, encryptedAmount.handles[0]),
      ).to.be.revertedWithCustomError(this.hookModule, 'ERC7984HookModuleUnauthorizedUseOfEncryptedAmount');
    });
  });

  describe('postTransfer', function () {
    it('should revert if the caller does not have access to the encrypted amount', async function () {
      const encryptedAmount = await fhevm
        .createEncryptedInput(this.hookModule.target, this.holder.address)
        .add64(100)
        .encrypt();
      await expect(
        this.hookModule.postTransfer(this.holder.address, this.recipient.address, encryptedAmount.handles[0]),
      ).to.be.revertedWithCustomError(this.hookModule, 'ERC7984HookModuleUnauthorizedUseOfEncryptedAmount');
    });
  });
});
