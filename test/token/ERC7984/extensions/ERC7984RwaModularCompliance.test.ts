import { callAndGetResult } from '../../../helpers/event';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { BytesLike } from 'ethers';
import { ethers, fhevm } from 'hardhat';

const transferEventSignature = 'ConfidentialTransfer(address,address,bytes32)';
const alwaysOnType = 0;
const transferOnlyType = 1;
const moduleTypes = [alwaysOnType, transferOnlyType];
const alwaysOn = 'always-on';
const transferOnly = 'transfer-only';
const maxInverstor = 2;
const maxBalance = 100;

const fixture = async () => {
  const [admin, agent1, agent2, recipient, anyone] = await ethers.getSigners();
  const token = (await ethers.deployContract('ERC7984RwaModularComplianceMock', ['name', 'symbol', 'uri'])).connect(
    anyone,
  );
  await token.connect(admin).addAgent(agent1);
  const alwaysOnModule = await ethers.deployContract('ERC7984RwaModularComplianceModuleMock', [
    await token.getAddress(),
    alwaysOn,
  ]);
  const transferOnlyModule = await ethers.deployContract('ERC7984RwaModularComplianceModuleMock', [
    await token.getAddress(),
    transferOnly,
  ]);
  const investorCapModule = await ethers.deployContract('ERC7984RwaInvestorCapModuleMock', [
    await token.getAddress(),
    maxInverstor,
  ]);
  const balanceCapModule = await ethers.deployContract('ERC7984RwaBalanceCapModuleMock', [await token.getAddress()]);
  const encryptedInput = await fhevm
    .createEncryptedInput(await balanceCapModule.getAddress(), admin.address)
    .add64(maxBalance)
    .encrypt();
  await balanceCapModule
    .connect(admin)
    ['setMaxBalance(bytes32,bytes)'](encryptedInput.handles[0], encryptedInput.inputProof);
  return {
    token,
    alwaysOnModule,
    transferOnlyModule,
    investorCapModule,
    balanceCapModule,
    admin,
    agent1,
    agent2,
    recipient,
    anyone,
  };
};

describe('ERC7984RwaModularCompliance', function () {
  describe('Support module', async function () {
    for (const type of moduleTypes) {
      it(`should support module type ${type}`, async function () {
        const { token } = await fixture();
        await expect(token.supportsModule(type)).to.eventually.be.true;
      });
    }
  });

  describe('Instal module', async function () {
    for (const type of moduleTypes) {
      it(`should install module type ${type}`, async function () {
        const { token, investorCapModule, admin } = await fixture();
        await expect(token.connect(admin).installModule(type, investorCapModule))
          .to.emit(token, 'ModuleInstalled')
          .withArgs(type, investorCapModule);
        await expect(token.isModuleInstalled(type, investorCapModule)).to.eventually.be.true;
      });
    }

    it('should not install module if not admin or agent', async function () {
      const { token, investorCapModule, anyone } = await fixture();
      await expect(token.connect(anyone).installModule(alwaysOnType, investorCapModule))
        .to.be.revertedWithCustomError(token, 'UnauthorizedSender')
        .withArgs(anyone.address);
    });

    for (const type of moduleTypes) {
      it('should not install module if not module', async function () {
        const { token, admin } = await fixture();
        const notModule = '0x0000000000000000000000000000000000000001';
        await expect(token.connect(admin).installModule(type, notModule))
          .to.be.revertedWithCustomError(token, 'ERC7984RwaNotTransferComplianceModule')
          .withArgs(notModule);
        await expect(token.isModuleInstalled(type, notModule)).to.eventually.be.false;
      });
    }

    for (const type of moduleTypes) {
      it(`should not install module type ${type} if already installed`, async function () {
        const { token, investorCapModule, admin } = await fixture();
        await token.connect(admin).installModule(type, investorCapModule);
        await expect(token.connect(admin).installModule(type, investorCapModule))
          .to.be.revertedWithCustomError(token, 'ERC7984RwaAlreadyInstalledModule')
          .withArgs(type, await investorCapModule.getAddress());
      });
    }
  });

  describe('Uninstal module', async function () {
    for (const type of moduleTypes) {
      it(`should remove module type ${type}`, async function () {
        const { token, investorCapModule, admin } = await fixture();
        await token.connect(admin).installModule(type, investorCapModule);
        await expect(token.connect(admin).uninstallModule(type, investorCapModule))
          .to.emit(token, 'ModuleUninstalled')
          .withArgs(type, investorCapModule);
        await expect(token.isModuleInstalled(type, investorCapModule)).to.eventually.be.false;
      });
    }
  });

  describe('Modules', async function () {
    for (const forceTransfer of [false, true]) {
      for (const compliant of [true, false]) {
        it(`should ${forceTransfer ? 'force transfer' : 'transfer'} ${
          compliant ? 'if' : 'zero if not'
        } compliant`, async function () {
          const { token, alwaysOnModule, transferOnlyModule, admin, recipient, anyone } = await fixture();
          await token.connect(admin).installModule(alwaysOnType, alwaysOnModule);
          await token.connect(admin).installModule(transferOnlyType, transferOnlyModule);
          const amount = 100;
          const encryptedMint = await fhevm
            .createEncryptedInput(await token.getAddress(), admin.address)
            .add64(amount)
            .encrypt();
          // set compliant for initial mint
          await alwaysOnModule.$_setCompliant();
          await transferOnlyModule.$_setCompliant();
          await token
            .connect(admin)
            ['confidentialMint(address,bytes32,bytes)'](
              recipient.address,
              encryptedMint.handles[0],
              encryptedMint.inputProof,
            );
          await expect(
            fhevm.userDecryptEuint(
              FhevmType.euint64,
              await token.confidentialBalanceOf(recipient.address),
              await token.getAddress(),
              recipient,
            ),
          ).to.eventually.equal(amount);
          const encryptedMint2 = await fhevm
            .createEncryptedInput(await token.getAddress(), admin.address)
            .add64(amount)
            .encrypt();
          if (compliant) {
            await alwaysOnModule.$_setCompliant();
            await transferOnlyModule.$_setCompliant();
          } else {
            await alwaysOnModule.$_unsetCompliant();
            await transferOnlyModule.$_unsetCompliant();
          }
          if (!forceTransfer) {
            await token.connect(recipient).setOperator(admin.address, (await time.latest()) + 1000);
          }
          const tx = token
            .connect(admin)
            [
              forceTransfer
                ? 'forceConfidentialTransferFrom(address,address,bytes32,bytes)'
                : 'confidentialTransferFrom(address,address,bytes32,bytes)'
            ](recipient.address, anyone.address, encryptedMint2.handles[0], encryptedMint2.inputProof);
          const [, , transferredHandle] = await callAndGetResult(tx, transferEventSignature);
          await expect(
            fhevm.userDecryptEuint(FhevmType.euint64, transferredHandle, await token.getAddress(), recipient),
          ).to.eventually.equal(compliant ? amount : 0);
          await expect(tx)
            .to.emit(alwaysOnModule, 'PreTransfer')
            .withArgs(alwaysOn)
            .to.emit(alwaysOnModule, 'PostTransfer')
            .withArgs(alwaysOn);
          if (forceTransfer) {
            await expect(tx)
              .to.not.emit(transferOnlyModule, 'PreTransfer')
              .to.not.emit(transferOnlyModule, 'PostTransfer');
          } else {
            await expect(tx)
              .to.emit(transferOnlyModule, 'PreTransfer')
              .withArgs(transferOnly)
              .to.emit(transferOnlyModule, 'PostTransfer')
              .withArgs(transferOnly);
          }
        });
      }
    }
  });

  describe('Balance cap module', async function () {
    for (const withProof of [false, true]) {
      it(`should set max balance ${withProof ? 'with proof' : ''}`, async function () {
        const { admin, balanceCapModule } = await fixture();
        let params = [] as unknown as [encryptedAmount: BytesLike, inputProof: BytesLike];
        if (withProof) {
          const { handles, inputProof } = await fhevm
            .createEncryptedInput(await balanceCapModule.getAddress(), admin.address)
            .add64(maxBalance + 100)
            .encrypt();
          params.push(handles[0], inputProof);
        } else {
          const [newBalance] = await callAndGetResult(
            balanceCapModule.connect(admin).createEncryptedAmount(maxBalance + 100),
            'AmountEncrypted(bytes32)',
          );
          params.push(newBalance);
        }
        await expect(
          balanceCapModule
            .connect(admin)
            [withProof ? 'setMaxBalance(bytes32,bytes)' : 'setMaxBalance(bytes32)'](...params),
        )
          .to.emit(balanceCapModule, 'MaxBalanceSet')
          .withArgs(params[0]);
        await balanceCapModule
          .connect(admin)
          .getHandleAllowance(await balanceCapModule.getMaxBalance(), admin.address, true);
        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await balanceCapModule.getMaxBalance(),
            await balanceCapModule.getAddress(),
            admin,
          ),
        ).to.eventually.equal(maxBalance + 100);
      });
    }
    for (const withProof of [false, true]) {
      it(`should not set max balance if not admin ${withProof ? 'with proof' : ''}`, async function () {
        const { admin, balanceCapModule, anyone } = await fixture();
        const [newBalance] = await callAndGetResult(
          balanceCapModule.connect(admin).createEncryptedAmount(maxBalance + 100),
          'AmountEncrypted(bytes32)',
        );
        const oldBalance = await balanceCapModule.getMaxBalance();
        const params = [newBalance];
        if (withProof) {
          params.push('0x');
        }
        await expect(
          balanceCapModule
            .connect(anyone)
            [withProof ? 'setMaxBalance(bytes32,bytes)' : 'setMaxBalance(bytes32)'](...params),
        )
          .to.be.revertedWithCustomError(balanceCapModule, 'SenderNotTokenAdmin')
          .withArgs(anyone.address);
        await expect(balanceCapModule.getMaxBalance()).to.eventually.equal(oldBalance);
      });
    }

    for (const type of moduleTypes) {
      it(`should transfer if compliant to balance cap module with type ${type}`, async function () {
        const { token, admin, balanceCapModule, recipient, anyone } = await fixture();
        await token.connect(admin).installModule(type, balanceCapModule);
        const encryptedMint = await fhevm
          .createEncryptedInput(await token.getAddress(), admin.address)
          .add64(100)
          .encrypt();
        await token
          .connect(admin)
          ['confidentialMint(address,bytes32,bytes)'](recipient, encryptedMint.handles[0], encryptedMint.inputProof);
        const amount = 25;
        const encryptedTransferValueInput = await fhevm
          .createEncryptedInput(await token.getAddress(), recipient.address)
          .add64(amount)
          .encrypt();
        const [, , transferredHandle] = await callAndGetResult(
          token
            .connect(recipient)
            ['confidentialTransfer(address,bytes32,bytes)'](
              anyone,
              encryptedTransferValueInput.handles[0],
              encryptedTransferValueInput.inputProof,
            ),
          transferEventSignature,
        );
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, transferredHandle, await token.getAddress(), recipient),
        ).to.eventually.equal(amount);
        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await token.confidentialBalanceOf(recipient),
            await token.getAddress(),
            recipient,
          ),
        ).to.eventually.equal(75);
      });
    }

    it(`should transfer zero if not compliant to balance cap module`, async function () {
      const { token, admin, balanceCapModule, recipient, anyone } = await fixture();
      await token.connect(admin).installModule(transferOnlyType, balanceCapModule);
      const encryptedMint = await fhevm
        .createEncryptedInput(await token.getAddress(), admin.address)
        .add64(100)
        .encrypt();
      await token
        .connect(admin)
        ['confidentialMint(address,bytes32,bytes)'](recipient, encryptedMint.handles[0], encryptedMint.inputProof);
      await token
        .connect(admin)
        ['confidentialMint(address,bytes32,bytes)'](anyone, encryptedMint.handles[0], encryptedMint.inputProof);
      const amount = 25;
      const encryptedTransferValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), recipient.address)
        .add64(amount)
        .encrypt();
      const [, , transferredHandle] = await callAndGetResult(
        token
          .connect(recipient)
          ['confidentialTransfer(address,bytes32,bytes)'](
            anyone,
            encryptedTransferValueInput.handles[0],
            encryptedTransferValueInput.inputProof,
          ),
        transferEventSignature,
      );
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferredHandle, await token.getAddress(), recipient),
      ).to.eventually.equal(0);
    });

    it('should transfer if compliant because burning', async function () {
      const { token, admin, balanceCapModule, recipient } = await fixture();
      await token.connect(admin).installModule(alwaysOnType, balanceCapModule);
      const encryptedMint = await fhevm
        .createEncryptedInput(await token.getAddress(), admin.address)
        .add64(100)
        .encrypt();
      await token
        .connect(admin)
        ['confidentialMint(address,bytes32,bytes)'](recipient, encryptedMint.handles[0], encryptedMint.inputProof);
      const amount = 25;
      const encryptedBurnValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), admin.address)
        .add64(amount)
        .encrypt();
      const [, , transferredHandle] = await callAndGetResult(
        token
          .connect(admin)
          ['confidentialBurn(address,bytes32,bytes)'](
            recipient,
            encryptedBurnValueInput.handles[0],
            encryptedBurnValueInput.inputProof,
          ),
        transferEventSignature,
      );
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferredHandle, await token.getAddress(), recipient),
      ).to.eventually.equal(25);
      await expect(
        fhevm.userDecryptEuint(
          FhevmType.euint64,
          await token.confidentialBalanceOf(recipient),
          await token.getAddress(),
          recipient,
        ),
      ).to.eventually.equal(75);
    });
  });

  describe('Investor cap module', async function () {
    for (const type of moduleTypes) {
      it(`should transfer if compliant to investor cap module else zero with type ${type}`, async function () {
        const { token, admin, investorCapModule, recipient, anyone } = await fixture();
        await token.connect(admin).installModule(type, investorCapModule);
        const encryptedMint = await fhevm
          .createEncryptedInput(await token.getAddress(), admin.address)
          .add64(100)
          .encrypt();
        for (const investor of [
          recipient.address, // investor#1
          ethers.Wallet.createRandom().address, //investor#2
        ]) {
          await token
            .connect(admin)
            ['confidentialMint(address,bytes32,bytes)'](investor, encryptedMint.handles[0], encryptedMint.inputProof);
        }
        await investorCapModule
          .connect(admin)
          .getHandleAllowance(await investorCapModule.getCurrentInvestor(), admin.address, true);
        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await investorCapModule.getCurrentInvestor(),
            await investorCapModule.getAddress(),
            admin,
          ),
        )
          .to.eventually.equal(await investorCapModule.getMaxInvestor())
          .to.equal(2);
        const amount = 25;
        const encryptedTransferValueInput = await fhevm
          .createEncryptedInput(await token.getAddress(), recipient.address)
          .add64(amount)
          .encrypt();
        // trying to transfer to investor#3 (anyone) but number of investors is capped
        const [, , transferredHandle] = await callAndGetResult(
          token
            .connect(recipient)
            ['confidentialTransfer(address,bytes32,bytes)'](
              anyone,
              encryptedTransferValueInput.handles[0],
              encryptedTransferValueInput.inputProof,
            ),
          transferEventSignature,
        );
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, transferredHandle, await token.getAddress(), recipient),
        ).to.eventually.equal(0);
        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await token.confidentialBalanceOf(recipient),
            await token.getAddress(),
            recipient,
          ),
        ).to.eventually.equal(100);
        // current investor should be unchanged
        await investorCapModule
          .connect(admin)
          .getHandleAllowance(await investorCapModule.getCurrentInvestor(), admin.address, true);
        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await investorCapModule.getCurrentInvestor(),
            await investorCapModule.getAddress(),
            admin,
          ),
        ).to.eventually.equal(2);
      });
    }

    it('should set max investor', async function () {
      const { token, admin, investorCapModule } = await fixture();
      const newMaxInvestor = 100;
      await token.connect(admin).installModule(alwaysOnType, investorCapModule);
      await expect(investorCapModule.connect(admin).setMaxInvestor(newMaxInvestor))
        .to.emit(investorCapModule, 'MaxInvestorSet')
        .withArgs(newMaxInvestor);
      await expect(investorCapModule.getMaxInvestor()).to.eventually.equal(newMaxInvestor);
    });

    it('should not set max investor if not admin', async function () {
      const { token, admin, anyone, investorCapModule } = await fixture();
      const newMaxInvestor = maxInverstor + 10;
      await token.connect(admin).installModule(alwaysOnType, investorCapModule);
      await expect(investorCapModule.connect(anyone).setMaxInvestor(newMaxInvestor))
        .to.be.revertedWithCustomError(investorCapModule, 'SenderNotTokenAdmin')
        .withArgs(anyone.address);
      await expect(investorCapModule.getMaxInvestor()).to.eventually.equal(maxInverstor);
    });
  });
});
