import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

/* eslint-disable no-unexpected-multiline */
describe('ERC7984Rwa', function () {
  async function deployFixture() {
    const [admin, agent1, agent2, recipient, anyone] = await ethers.getSigners();
    const token = await ethers.deployContract('ERC7984RwaMock', ['name', 'symbol', 'uri']);
    await token
      .connect(admin)
      .addAgent(agent1)
      .then(tx => tx.wait());
    token.connect(anyone);
    return { token, admin, agent1, agent2, recipient, anyone };
  }

  describe('Pausable', async function () {
    it('should pause & unpause', async function () {
      const { token, admin, agent1 } = await deployFixture();
      for (const manager of [admin, agent1]) {
        expect(await token.paused()).is.false;
        await token
          .connect(manager)
          .pause()
          .then(tx => tx.wait());
        expect(await token.paused()).is.true;
        await token
          .connect(manager)
          .unpause()
          .then(tx => tx.wait());
        expect(await token.paused()).is.false;
      }
    });

    it('should not pause if neither admin nor agent', async function () {
      const { token, anyone } = await deployFixture();
      await expect(token.connect(anyone).pause())
        .to.be.revertedWithCustomError(token, 'UnauthorizedSender')
        .withArgs(anyone);
    });

    it('should not unpause if neither admin nor agent', async function () {
      const { token, anyone } = await deployFixture();
      await expect(token.connect(anyone).unpause())
        .to.be.revertedWithCustomError(token, 'UnauthorizedSender')
        .withArgs(anyone);
    });
  });

  describe('Roles', async function () {
    it('should check admin', async function () {
      const { token, admin, anyone } = await deployFixture();
      expect(await token.isAdmin(admin)).is.true;
      expect(await token.isAdmin(anyone)).is.false;
    });

    it('should check/add/remove agent', async function () {
      const { token, admin, agent1, agent2 } = await deployFixture();
      for (const manager of [admin, agent1]) {
        expect(await token.isAgent(agent2)).is.false;
        await token
          .connect(manager)
          .addAgent(agent2)
          .then(tx => tx.wait());
        expect(await token.isAgent(agent2)).is.true;
        await token
          .connect(manager)
          .removeAgent(agent2)
          .then(tx => tx.wait());
        expect(await token.isAgent(agent2)).is.false;
      }
    });

    it('should not add agent if neither admin nor agent', async function () {
      const { token, agent1, anyone } = await deployFixture();
      await expect(token.connect(anyone).addAgent(agent1))
        .to.be.revertedWithCustomError(token, 'UnauthorizedSender')
        .withArgs(anyone);
    });

    it('should not remove agent if neither admin nor agent', async function () {
      const { token, agent1, anyone } = await deployFixture();
      await expect(token.connect(anyone).removeAgent(agent1))
        .to.be.revertedWithCustomError(token, 'UnauthorizedSender')
        .withArgs(anyone);
    });
  });

  describe('Mintable', async function () {
    it('should mint by admin or agent', async function () {
      const { admin, agent1, recipient } = await deployFixture();
      for (const manager of [admin, agent1]) {
        const { token } = await deployFixture();
        const encryptedInput = await fhevm
          .createEncryptedInput(await token.getAddress(), manager.address)
          .add64(100)
          .encrypt();
        await token.$_setCompliantTransfer().then(tx => tx.wait());
        await token
          .connect(manager)
          ['mint(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof)
          .then(tx => tx.wait());
        const balanceHandle = await token.confidentialBalanceOf(recipient);
        await token
          .connect(manager)
          .getHandleAllowance(balanceHandle, manager, true)
          .then(tx => tx.wait());
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceHandle, await token.getAddress(), manager),
        ).to.eventually.equal(100);
      }
    });

    it('should not mint if neither admin nor agent', async function () {
      const { token, recipient, anyone } = await deployFixture();
      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), anyone.address)
        .add64(100)
        .encrypt();
      await expect(
        token
          .connect(anyone)
          ['mint(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(token, 'UnauthorizedSender')
        .withArgs(anyone);
    });

    it('should not mint if transfer not compliant', async function () {
      const { token, admin, recipient } = await deployFixture();
      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), admin.address)
        .add64(100)
        .encrypt();
      await expect(
        token
          .connect(admin)
          ['mint(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(token, 'UncompliantTransfer')
        .withArgs(ethers.ZeroAddress, recipient, encryptedInput.handles[0]);
    });

    it('should not mint if paused', async function () {
      const { token, admin, recipient } = await deployFixture();
      await token
        .connect(admin)
        .pause()
        .then(tx => tx.wait());
      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), admin.address)
        .add64(100)
        .encrypt();
      await expect(
        token
          .connect(admin)
          ['mint(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof),
      ).to.be.revertedWithCustomError(token, 'EnforcedPause');
    });
  });

  describe('Burnable', async function () {
    it('should burn by admin or agent', async function () {
      const { admin, agent1, recipient } = await deployFixture();
      for (const manager of [admin, agent1]) {
        const { token } = await deployFixture();
        const encryptedInput = await fhevm
          .createEncryptedInput(await token.getAddress(), manager.address)
          .add64(100)
          .encrypt();
        await token.$_setCompliantTransfer().then(tx => tx.wait());
        await token
          .connect(manager)
          ['mint(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof)
          .then(tx => tx.wait());
        const balanceBeforeHandle = await token.confidentialBalanceOf(recipient);
        await token
          .connect(manager)
          .getHandleAllowance(balanceBeforeHandle, manager, true)
          .then(tx => tx.wait());
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceBeforeHandle, await token.getAddress(), manager),
        ).to.eventually.greaterThan(0);
        await token
          .connect(manager)
          ['burn(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof)
          .then(tx => tx.wait());
        const balanceHandle = await token.confidentialBalanceOf(recipient);
        await token
          .connect(manager)
          .getHandleAllowance(balanceHandle, manager, true)
          .then(tx => tx.wait());
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceHandle, await token.getAddress(), manager),
        ).to.eventually.equal(0);
      }
    });

    it('should not burn if neither admin nor agent', async function () {
      const { token, recipient, anyone } = await deployFixture();
      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), anyone.address)
        .add64(100)
        .encrypt();
      await expect(
        token
          .connect(anyone)
          ['burn(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(token, 'UnauthorizedSender')
        .withArgs(anyone);
    });

    it('should not mint if transfer not compliant', async function () {
      const { token, admin, recipient } = await deployFixture();
      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), admin.address)
        .add64(100)
        .encrypt();
      await expect(
        token
          .connect(admin)
          ['burn(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(token, 'UncompliantTransfer')
        .withArgs(recipient, ethers.ZeroAddress, encryptedInput.handles[0]);
    });

    it('should not burn if paused', async function () {
      const { token, admin, recipient } = await deployFixture();
      await token
        .connect(admin)
        .pause()
        .then(tx => tx.wait());
      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), admin.address)
        .add64(100)
        .encrypt();
      await expect(
        token
          .connect(admin)
          ['burn(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof),
      ).to.be.revertedWithCustomError(token, 'EnforcedPause');
    });
  });

  describe('Force transfer', async function () {
    it('should force transfer by admin or agent', async function () {
      const { admin, agent1, recipient, anyone } = await deployFixture();
      for (const manager of [admin, agent1]) {
        const { token } = await deployFixture();
        const encryptedMintValueInput = await fhevm
          .createEncryptedInput(await token.getAddress(), manager.address)
          .add64(100)
          .encrypt();
        await token.$_setCompliantTransfer().then(tx => tx.wait());
        await token
          .connect(manager)
          ['mint(address,bytes32,bytes)'](
            recipient,
            encryptedMintValueInput.handles[0],
            encryptedMintValueInput.inputProof,
          )
          .then(tx => tx.wait());
        // set frozen (50 available and about to force transfer 25)
        const encryptedFrozenValueInput = await fhevm
          .createEncryptedInput(await token.getAddress(), manager.address)
          .add64(50)
          .encrypt();
        await token
          .connect(manager)
          ['setConfidentialFrozen(address,bytes32,bytes)'](
            recipient,
            encryptedFrozenValueInput.handles[0],
            encryptedFrozenValueInput.inputProof,
          )
          .then(tx => tx.wait());
        const encryptedTransferValueInput = await fhevm
          .createEncryptedInput(await token.getAddress(), manager.address)
          .add64(25)
          .encrypt();
        await token.$_unsetCompliantTransfer().then(tx => tx.wait());
        expect(await token.compliantTransfer()).to.be.false;
        await token
          .connect(manager)
          ['forceTransfer(address,address,bytes32,bytes)'](
            recipient,
            anyone,
            encryptedTransferValueInput.handles[0],
            encryptedTransferValueInput.inputProof,
          )
          .then(tx => tx.wait());
        const balanceHandle = await token.confidentialBalanceOf(recipient);
        await token
          .connect(manager)
          .getHandleAllowance(balanceHandle, manager, true)
          .then(tx => tx.wait());
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceHandle, await token.getAddress(), manager),
        ).to.eventually.equal(75);
        const frozenHandle = await token.confidentialFrozen(recipient);
        await token
          .connect(manager)
          .getHandleAllowance(frozenHandle, manager, true)
          .then(tx => tx.wait());
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, frozenHandle, await token.getAddress(), manager),
        ).to.eventually.equal(50); // frozen is left unchanged
      }
    });

    it('should force transfer even if frozen', async function () {
      const { admin, agent1, recipient, anyone } = await deployFixture();
      for (const manager of [admin, agent1]) {
        const { token } = await deployFixture();
        const encryptedMintValueInput = await fhevm
          .createEncryptedInput(await token.getAddress(), manager.address)
          .add64(100)
          .encrypt();
        await token.$_setCompliantTransfer().then(tx => tx.wait());
        await token
          .connect(manager)
          ['mint(address,bytes32,bytes)'](
            recipient,
            encryptedMintValueInput.handles[0],
            encryptedMintValueInput.inputProof,
          )
          .then(tx => tx.wait());
        // set frozen (only 20 available but about to force transfer 25)
        const encryptedFrozenValueInput = await fhevm
          .createEncryptedInput(await token.getAddress(), manager.address)
          .add64(80)
          .encrypt();
        await token
          .connect(manager)
          ['setConfidentialFrozen(address,bytes32,bytes)'](
            recipient,
            encryptedFrozenValueInput.handles[0],
            encryptedFrozenValueInput.inputProof,
          )
          .then(tx => tx.wait());
        const encryptedTransferValueInput = await fhevm
          .createEncryptedInput(await token.getAddress(), manager.address)
          .add64(25)
          .encrypt();
        await token.$_unsetCompliantTransfer().then(tx => tx.wait());
        expect(await token.compliantTransfer()).to.be.false;
        // should force transfer even if paused
        await token
          .connect(manager)
          .pause()
          .then(tx => tx.wait());
        expect(await token.paused()).to.be.true;
        await token
          .connect(manager)
          ['forceTransfer(address,address,bytes32,bytes)'](
            recipient,
            anyone,
            encryptedTransferValueInput.handles[0],
            encryptedTransferValueInput.inputProof,
          )
          .then(tx => tx.wait());
        const balanceHandle = await token.confidentialBalanceOf(recipient);
        await token
          .connect(manager)
          .getHandleAllowance(balanceHandle, manager, true)
          .then(tx => tx.wait());
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceHandle, await token.getAddress(), manager),
        ).to.eventually.equal(75);
        const frozenHandle = await token.confidentialFrozen(recipient);
        await token
          .connect(manager)
          .getHandleAllowance(frozenHandle, manager, true)
          .then(tx => tx.wait());
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, frozenHandle, await token.getAddress(), manager),
        ).to.eventually.equal(75); // frozen got reset to available balance
      }
    });
  });

  describe('Transfer', async function () {
    it('should transfer', async function () {
      const { token, admin: manager, recipient, anyone } = await deployFixture();
      const encryptedMintValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), manager.address)
        .add64(100)
        .encrypt();
      await token.$_setCompliantTransfer().then(tx => tx.wait());
      await token
        .connect(manager)
        ['mint(address,bytes32,bytes)'](
          recipient,
          encryptedMintValueInput.handles[0],
          encryptedMintValueInput.inputProof,
        )
        .then(tx => tx.wait());
      // set frozen (50 available and about to transfer 25)
      const encryptedFrozenValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), manager.address)
        .add64(50)
        .encrypt();
      await token
        .connect(manager)
        ['setConfidentialFrozen(address,bytes32,bytes)'](
          recipient,
          encryptedFrozenValueInput.handles[0],
          encryptedFrozenValueInput.inputProof,
        )
        .then(tx => tx.wait());
      const encryptedTransferValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), recipient.address)
        .add64(25)
        .encrypt();
      await token.$_setCompliantTransfer().then(tx => tx.wait());
      expect(await token.compliantTransfer()).to.be.true;
      await expect(
        token
          .connect(recipient)
          ['confidentialTransfer(address,bytes32,bytes)'](
            anyone,
            encryptedTransferValueInput.handles[0],
            encryptedTransferValueInput.inputProof,
          ),
      ).to.emit(token, 'ConfidentialTransfer');
      await expect(
        fhevm.userDecryptEuint(
          FhevmType.euint64,
          await token.confidentialBalanceOf(recipient),
          await token.getAddress(),
          recipient,
        ),
      ).to.eventually.equal(75);
    });

    it('should not transfer if paused', async function () {
      const { token, admin: manager, recipient, anyone } = await deployFixture();
      const encryptedTransferValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), recipient.address)
        .add64(25)
        .encrypt();
      await token
        .connect(manager)
        .pause()
        .then(tx => tx.wait());
      await expect(
        token
          .connect(recipient)
          ['confidentialTransfer(address,bytes32,bytes)'](
            anyone,
            encryptedTransferValueInput.handles[0],
            encryptedTransferValueInput.inputProof,
          ),
      ).to.be.revertedWithCustomError(token, 'EnforcedPause');
    });

    it('should not transfer if transfer not compliant', async function () {
      const { token, recipient, anyone } = await deployFixture();
      const encryptedTransferValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), recipient.address)
        .add64(25)
        .encrypt();
      expect(await token.compliantTransfer()).to.be.false;
      await expect(
        token
          .connect(recipient)
          ['confidentialTransfer(address,bytes32,bytes)'](
            anyone,
            encryptedTransferValueInput.handles[0],
            encryptedTransferValueInput.inputProof,
          ),
      )
        .to.be.revertedWithCustomError(token, 'UncompliantTransfer')
        .withArgs(recipient, anyone, encryptedTransferValueInput.handles[0]);
    });

    it('should not transfer if frozen', async function () {
      const { token, admin: manager, recipient, anyone } = await deployFixture();
      const encryptedMintValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), manager.address)
        .add64(100)
        .encrypt();
      await token.$_setCompliantTransfer().then(tx => tx.wait());
      await token
        .connect(manager)
        ['mint(address,bytes32,bytes)'](
          recipient,
          encryptedMintValueInput.handles[0],
          encryptedMintValueInput.inputProof,
        )
        .then(tx => tx.wait());
      // set frozen (20 available but about to transfer 25)
      const encryptedFrozenValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), manager.address)
        .add64(80)
        .encrypt();
      await token
        .connect(manager)
        ['setConfidentialFrozen(address,bytes32,bytes)'](
          recipient,
          encryptedFrozenValueInput.handles[0],
          encryptedFrozenValueInput.inputProof,
        )
        .then(tx => tx.wait());
      const encryptedTransferValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), recipient.address)
        .add64(25)
        .encrypt();
      await token.$_setCompliantTransfer().then(tx => tx.wait());
      expect(await token.compliantTransfer()).to.be.true;
      await expect(
        token
          .connect(recipient)
          ['confidentialTransfer(address,bytes32,bytes)'](
            anyone,
            encryptedTransferValueInput.handles[0],
            encryptedTransferValueInput.inputProof,
          ),
      ).to.emit(token, 'ConfidentialTransfer');
      /* TODO: Enable when freezable ready
      // Balance is unchanged
      await expect(
        fhevm.userDecryptEuint(
          FhevmType.euint64,
          await token.confidentialBalanceOf(recipient),
          await token.getAddress(),
          recipient,
        ),
      ).to.eventually.equal(100);
      */
    });
  });
});
/* eslint-disable no-unexpected-multiline */
