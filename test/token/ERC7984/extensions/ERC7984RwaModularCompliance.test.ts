import { $ERC7984RwaModularCompliance } from '../../../../types/contracts-exposed/token/ERC7984/extensions/rwa/ERC7984RwaModularCompliance.sol/$ERC7984RwaModularCompliance';
import { callAndGetResult } from '../../../helpers/event';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

enum ModuleType {
  Default,
  ForceTransfer,
}

const transferEventSignature = 'ConfidentialTransfer(address,address,bytes32)';
const adminRole = ethers.ZeroHash;

const fixture = async () => {
  const [admin, agent1, agent2, holder, recipient, anyone] = await ethers.getSigners();
  const token = (
    await ethers.deployContract('$ERC7984RwaModularComplianceMock', ['name', 'symbol', 'uri', admin])
  ).connect(anyone) as $ERC7984RwaModularCompliance;
  await token.connect(admin).addAgent(agent1);
  const complianceModule = await ethers.deployContract('$ComplianceModuleConfidentialMock');

  return {
    token,
    holder,
    complianceModule,
    admin,
    agent1,
    agent2,
    recipient,
    anyone,
  };
};

describe('ERC7984RwaModularCompliance', function () {
  beforeEach(async function () {
    const [admin, agent1, agent2, holder, recipient, anyone] = await ethers.getSigners();
    const token = (
      await ethers.deployContract('$ERC7984RwaModularComplianceMock', ['name', 'symbol', 'uri', admin])
    ).connect(anyone) as $ERC7984RwaModularCompliance;
    await token.connect(admin).addAgent(agent1);
    const complianceModule = await ethers.deployContract('$ComplianceModuleConfidentialMock');

    Object.assign(this, {
      token,
      complianceModule,
      admin,
      agent1,
      agent2,
      recipient,
      holder,
      anyone,
    });
  });

  describe('support module', async function () {
    for (const type of [ModuleType.Default, ModuleType.ForceTransfer]) {
      it(`should support module type ${ModuleType[type]}`, async function () {
        await expect(this.token.supportsModule(type)).to.eventually.be.true;
      });

      it('should not support other module types', async function () {
        await expect(this.token.supportsModule(3)).to.be.reverted;
      });
    }
  });

  describe('install module', async function () {
    it('should emit event', async function () {
      await expect(this.token.$_installModule(ModuleType.Default, this.complianceModule, '0x'))
        .to.emit(this.token, 'ModuleInstalled')
        .withArgs(ModuleType.Default, this.complianceModule);
    });

    it('should call `onInstall` on the module', async function () {
      await expect(this.token.$_installModule(ModuleType.Default, this.complianceModule, '0xffff'))
        .to.emit(this.complianceModule, 'OnInstall')
        .withArgs('0xffff');
    });

    for (const type of [ModuleType.Default, ModuleType.ForceTransfer]) {
      it(`should add ${ModuleType[type]} module to modules list`, async function () {
        await this.token.$_installModule(type, this.complianceModule, '0x');
        await expect(this.token.isModuleInstalled(type, this.complianceModule)).to.eventually.be.true;
      });
    }

    it('should gate to admin', async function () {
      await expect(this.token.connect(this.anyone).installModule(ModuleType.Default, this.complianceModule, '0x'))
        .to.be.revertedWithCustomError(this.token, 'AccessControlUnauthorizedAccount')
        .withArgs(this.anyone, adminRole);
    });

    it('should run module check', async function () {
      const notModule = '0x0000000000000000000000000000000000000001';
      await expect(this.token.connect(this.admin).installModule(ModuleType.Default, notModule, '0x'))
        .to.be.revertedWithCustomError(this.token, 'ERC7984RwaNotTransferComplianceModule')
        .withArgs(notModule);
    });

    it('should not install module if already installed', async function () {
      await this.token.$_installModule(ModuleType.Default, this.complianceModule, '0x');
      await expect(this.token.$_installModule(ModuleType.Default, this.complianceModule, '0x'))
        .to.be.revertedWithCustomError(this.token, 'ERC7984RwaAlreadyInstalledModule')
        .withArgs(ModuleType.Default, this.complianceModule);
    });
  });

  describe('uninstall module', async function () {
    beforeEach(async function () {
      for (const type of [ModuleType.Default, ModuleType.ForceTransfer]) {
        await this.token.$_installModule(type, this.complianceModule, '0x');
      }
    });

    it('should emit event', async function () {
      await expect(this.token.$_uninstallModule(ModuleType.Default, this.complianceModule, '0x'))
        .to.emit(this.token, 'ModuleUninstalled')
        .withArgs(ModuleType.Default, this.complianceModule);
    });

    it('should fail if module not installed', async function () {
      const newComplianceModule = await ethers.deployContract('$ComplianceModuleConfidentialMock');

      await expect(this.token.$_uninstallModule(ModuleType.Default, newComplianceModule, '0x'))
        .to.be.revertedWithCustomError(this.token, 'ERC7984RwaAlreadyUninstalledModule')
        .withArgs(ModuleType.Default, newComplianceModule);
    });

    it('should call `onUninstall` on the module', async function () {
      await expect(this.token.$_uninstallModule(ModuleType.Default, this.complianceModule, '0xffff'))
        .to.emit(this.complianceModule, 'OnUninstall')
        .withArgs('0xffff');
    });

    for (const type of [ModuleType.Default, ModuleType.ForceTransfer]) {
      it(`should remove module of type ${ModuleType[type]} from modules list`, async function () {
        await this.token.$_uninstallModule(type, this.complianceModule, '0x');
        await expect(this.token.isModuleInstalled(type, this.complianceModule)).to.eventually.be.false;
      });
    }

    it("should not revert if module's `onUninstall` reverts", async function () {
      await this.complianceModule.setRevertOnUninstall(true);
      await this.token.$_uninstallModule(ModuleType.Default, this.complianceModule, '0x');
    });

    it('should gate to admin', async function () {
      await expect(this.token.connect(this.anyone).uninstallModule(ModuleType.Default, this.complianceModule, '0x'))
        .to.be.revertedWithCustomError(this.token, 'AccessControlUnauthorizedAccount')
        .withArgs(this.anyone, adminRole);
    });
  });

  describe('check compliance on transfer', async function () {
    beforeEach(async function () {
      await this.token.$_installModule(ModuleType.Default, this.complianceModule, '0x');
      await this.token['$_mint(address,uint64)'](this.holder, 1000);

      const forceTransferModule = await ethers.deployContract('$ComplianceModuleConfidentialMock');
      await this.token.$_installModule(ModuleType.ForceTransfer, forceTransferModule, '0x');
      this.forceTransferModule = forceTransferModule;
    });

    it('should call pre-transfer hooks', async function () {
      await expect(this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 100n))
        .to.emit(this.complianceModule, 'PreTransfer')
        .to.emit(this.forceTransferModule, 'PreTransfer');
    });

    it('should call post-transfer hooks', async function () {
      await expect(this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 100n))
        .to.emit(this.complianceModule, 'PostTransfer')
        .to.emit(this.forceTransferModule, 'PostTransfer');
    });

    for (const approve of [true, false]) {
      it(`should react correctly to compliance ${approve ? 'approval' : 'denial'}`, async function () {
        await this.complianceModule.setIsCompliant(approve);
        await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 100n);

        const recipientBalance = await this.token.confidentialBalanceOf(this.recipient);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, recipientBalance, this.token.target, this.recipient),
        ).to.eventually.equal(approve ? 100 : 0);
      });
    }

    describe('force transfer', function () {
      it('should only call pre-transfer hook on force transfer module', async function () {
        const encryptedAmount = await fhevm
          .createEncryptedInput(this.token.target, this.agent1.address)
          .add64(100n)
          .encrypt();

        await expect(
          this.token
            .connect(this.agent1)
            ['forceConfidentialTransferFrom(address,address,bytes32,bytes)'](
              this.holder,
              this.recipient,
              encryptedAmount.handles[0],
              encryptedAmount.inputProof,
            ),
        )
          .to.emit(this.forceTransferModule, 'PreTransfer')
          .to.not.emit(this.complianceModule, 'PreTransfer');
      });

      it('should call post-transfer hook on all compliance modules', async function () {
        const encryptedAmount = await fhevm
          .createEncryptedInput(this.token.target, this.agent1.address)
          .add64(100n)
          .encrypt();

        await expect(
          this.token
            .connect(this.agent1)
            ['forceConfidentialTransferFrom(address,address,bytes32,bytes)'](
              this.holder,
              this.recipient,
              encryptedAmount.handles[0],
              encryptedAmount.inputProof,
            ),
        )
          .to.emit(this.forceTransferModule, 'PostTransfer')
          .to.emit(this.complianceModule, 'PostTransfer');
      });

      it('should pass compliance if default module fails', async function () {
        await this.complianceModule.setIsCompliant(false);

        const encryptedAmount = await fhevm
          .createEncryptedInput(this.token.target, this.agent1.address)
          .add64(100n)
          .encrypt();

        await this.token
          .connect(this.agent1)
          ['forceConfidentialTransferFrom(address,address,bytes32,bytes)'](
            this.holder,
            this.recipient,
            encryptedAmount.handles[0],
            encryptedAmount.inputProof,
          );

        const recipientBalance = await this.token.confidentialBalanceOf(this.recipient);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, recipientBalance, this.token.target, this.recipient),
        ).to.eventually.equal(100);
      });

      it('should fail compliance if force transfer module does not pass', async function () {
        await this.forceTransferModule.setIsCompliant(false);

        const encryptedAmount = await fhevm
          .createEncryptedInput(this.token.target, this.agent1.address)
          .add64(100n)
          .encrypt();

        await this.token
          .connect(this.agent1)
          ['forceConfidentialTransferFrom(address,address,bytes32,bytes)'](
            this.holder,
            this.recipient,
            encryptedAmount.handles[0],
            encryptedAmount.inputProof,
          );

        const recipientBalance = await this.token.confidentialBalanceOf(this.recipient);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, recipientBalance, this.token.target, this.recipient),
        ).to.eventually.equal(0);
      });
    });
  });
});
