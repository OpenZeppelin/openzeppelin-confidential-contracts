import { $ERC7984Hooked } from '../../../../types/contracts-exposed/token/ERC7984/extensions/rwa/ERC7984Hooked.sol/$ERC7984Hooked';
import { INTERFACE_IDS, INVALID_ID } from '../../../helpers/interface';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

describe('ERC7984Hooked', function () {
  beforeEach(async function () {
    const [admin, holder, recipient, anyone] = await ethers.getSigners();
    const token = (await ethers.deployContract('$ERC7984HookedMock', ['name', 'symbol', 'uri', admin])).connect(
      anyone,
    ) as $ERC7984Hooked;
    const hookModule = await ethers.deployContract('$ERC7984HookModuleMock');

    Object.assign(this, {
      token,
      hookModule,
      admin,
      recipient,
      holder,
      anyone,
    });
  });

  describe('ERC165', async function () {
    it('should support interface', async function () {
      await expect(this.token.supportsInterface(INTERFACE_IDS.ERC7984)).to.eventually.be.true;
      await expect(this.token.supportsInterface(INTERFACE_IDS.ERC7984Hooked)).to.eventually.be.true;
    });

    it('should not support interface', async function () {
      await expect(this.token.supportsInterface(INVALID_ID)).to.eventually.be.false;
    });
  });

  describe('install module', async function () {
    it('should emit event', async function () {
      await expect(this.token.$_installModule(this.hookModule, '0x'))
        .to.emit(this.token, 'ModuleInstalled')
        .withArgs(this.hookModule);
    });

    it('should call `onInstall` on the module', async function () {
      await expect(this.token.$_installModule(this.hookModule, '0xffff'))
        .to.emit(this.hookModule, 'OnInstall')
        .withArgs('0xffff');
    });

    it('should add module to modules list', async function () {
      await this.token.$_installModule(this.hookModule, '0x');
      await expect(this.token.isModuleInstalled(this.hookModule)).to.eventually.be.true;
    });

    it('should gate to owner', async function () {
      await expect(this.token.connect(this.anyone).installModule(this.hookModule, '0x'))
        .to.be.revertedWithCustomError(this.token, 'OwnableUnauthorizedAccount')
        .withArgs(this.anyone);

      await this.token.connect(this.admin).installModule(this.hookModule, '0x');
    });

    it('should run module check', async function () {
      const notModule = '0x0000000000000000000000000000000000000001';
      await expect(this.token.$_installModule(notModule, '0x'))
        .to.be.revertedWithCustomError(this.token, 'ERC7984HookedInvalidModule')
        .withArgs(notModule);
    });

    it('should not install module if max modules exceeded', async function () {
      const max = Number(await this.token.maxModules());

      for (let i = 0; i < max; i++) {
        const module = await ethers.deployContract('$ERC7984HookModuleMock');
        await this.token.$_installModule(module, '0x');
      }

      const extraModule = await ethers.deployContract('$ERC7984HookModuleMock');
      await expect(this.token.$_installModule(extraModule, '0x')).to.be.revertedWithCustomError(
        this.token,
        'ERC7984HookedExceededMaxModules',
      );
    });

    it('should not install module if already installed', async function () {
      await this.token.$_installModule(this.hookModule, '0x');
      await expect(this.token.$_installModule(this.hookModule, '0x'))
        .to.be.revertedWithCustomError(this.token, 'ERC7984HookedDuplicateModule')
        .withArgs(this.hookModule);
    });
  });

  describe('uninstall module', async function () {
    beforeEach(async function () {
      await this.token.$_installModule(this.hookModule, '0x');
    });

    it('should emit event', async function () {
      await expect(this.token.$_uninstallModule(this.hookModule, '0x'))
        .to.emit(this.token, 'ModuleUninstalled')
        .withArgs(this.hookModule);
    });

    it('should fail if module not installed', async function () {
      const newModule = await ethers.deployContract('$ERC7984HookModuleMock');

      await expect(this.token.$_uninstallModule(newModule, '0x'))
        .to.be.revertedWithCustomError(this.token, 'ERC7984HookedNonexistentModule')
        .withArgs(newModule);
    });

    it('should call `onUninstall` on the module', async function () {
      await expect(this.token.$_uninstallModule(this.hookModule, '0xffff'))
        .to.emit(this.hookModule, 'OnUninstall')
        .withArgs('0xffff');
    });

    it('should remove module from modules list', async function () {
      await this.token.$_uninstallModule(this.hookModule, '0x');
      await expect(this.token.isModuleInstalled(this.hookModule)).to.eventually.be.false;
    });

    it("should not revert if module's `onUninstall` reverts", async function () {
      await this.hookModule.setRevertOnUninstall(true);
      await this.token.$_uninstallModule(this.hookModule, '0x');
    });

    it('should gate to owner', async function () {
      await expect(this.token.connect(this.anyone).uninstallModule(this.hookModule, '0x'))
        .to.be.revertedWithCustomError(this.token, 'OwnableUnauthorizedAccount')
        .withArgs(this.anyone);

      await this.token.connect(this.admin).uninstallModule(this.hookModule, '0x');
      await expect(this.token.isModuleInstalled(this.hookModule)).to.eventually.be.false;
    });
  });

  describe('hooks on transfer', async function () {
    beforeEach(async function () {
      await this.token.$_installModule(this.hookModule, '0x');
      await this.token['$_mint(address,uint64)'](this.holder, 1000);
    });

    it('should call pre-transfer hooks', async function () {
      await expect(
        this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 100n),
      ).to.emit(this.hookModule, 'PreTransfer');
    });

    it('should call post-transfer hooks', async function () {
      await expect(
        this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 100n),
      ).to.emit(this.hookModule, 'PostTransfer');
    });

    for (const approve of [true, false]) {
      it(`should react correctly to module ${approve ? 'approval' : 'denial'}`, async function () {
        await this.hookModule.setIsCompliant(approve);
        await this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, 100n);

        const recipientBalance = await this.token.confidentialBalanceOf(this.recipient);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, recipientBalance, this.token.target, this.recipient),
        ).to.eventually.equal(approve ? 100 : 0);
      });
    }
  });
});
