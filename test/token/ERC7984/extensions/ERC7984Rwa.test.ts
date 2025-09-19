import { IAccessControl__factory, IERC165__factory, IERC7984__factory, IERC7984Rwa__factory } from '../../../../types';
import { callAndGetResult } from '../../../helpers/event';
import { getFunctions, getInterfaceId } from '../../../helpers/interface';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { AddressLike, BytesLike } from 'ethers';
import { ethers, fhevm } from 'hardhat';

const transferEventSignature = 'ConfidentialTransfer(address,address,bytes32)';
const frozenEventSignature = 'TokensFrozen(address,bytes32)';
const adminRole = ethers.ZeroHash;
const agentRole = ethers.id('AGENT_ROLE');

const fixture = async () => {
  const [admin, agent1, agent2, recipient, anyone] = await ethers.getSigners();
  const token = await ethers.deployContract('ERC7984RwaMock', ['name', 'symbol', 'uri']);
  await token.connect(admin).addAgent(agent1);
  token.connect(anyone);
  return { token, admin, agent1, agent2, recipient, anyone };
};

describe('ERC7984Rwa', function () {
  describe('ERC165', async function () {
    it('should support interface', async function () {
      const { token } = await fixture();
      const erc7984RwaFunctions = [IERC7984Rwa__factory, IERC7984__factory, IERC165__factory].flatMap(
        interfaceFactory => getFunctions(interfaceFactory),
      );
      const erc7984Functions = getFunctions(IERC7984__factory);
      const erc165Functions = getFunctions(IERC165__factory);
      for (let functions of [erc7984RwaFunctions, erc7984Functions, erc165Functions]) {
        expect(await token.supportsInterface(getInterfaceId(functions))).is.true;
      }
    });
    it('should not support interface', async function () {
      const { token } = await fixture();
      expect(await token.supportsInterface('0xbadbadba')).is.false;
    });
  });

  describe('Pausable', async function () {
    it('should pause & unpause', async function () {
      const { token, agent1 } = await fixture();
      expect(await token.paused()).is.false;
      await token.connect(agent1).pause();
      expect(await token.paused()).is.true;
      await token.connect(agent1).unpause();
      expect(await token.paused()).is.false;
    });

    it('should not pause if not agent', async function () {
      const { token, anyone } = await fixture();
      await expect(token.connect(anyone).pause())
        .to.be.revertedWithCustomError(token, 'AccessControlUnauthorizedAccount')
        .withArgs(anyone.address, agentRole);
    });

    it('should not unpause if not agent', async function () {
      const { token, anyone } = await fixture();
      await expect(token.connect(anyone).unpause())
        .to.be.revertedWithCustomError(token, 'AccessControlUnauthorizedAccount')
        .withArgs(anyone.address, agentRole);
    });
  });

  describe('Roles', async function () {
    it('should check admin', async function () {
      const { token, admin, anyone } = await fixture();
      expect(await token.isAdmin(admin)).is.true;
      expect(await token.isAdmin(anyone)).is.false;
    });

    it('should check/add/remove agent', async function () {
      const { token, admin, agent2 } = await fixture();
      expect(await token.isAgent(agent2)).is.false;
      await token.connect(admin).addAgent(agent2);
      expect(await token.isAgent(agent2)).is.true;
      await token.connect(admin).removeAgent(agent2);
      expect(await token.isAgent(agent2)).is.false;
    });

    it('should not add agent if not admin', async function () {
      const { token, agent1, anyone } = await fixture();
      await expect(token.connect(anyone).addAgent(agent1))
        .to.be.revertedWithCustomError(token, 'AccessControlUnauthorizedAccount')
        .withArgs(anyone.address, adminRole);
    });

    it('should not remove agent if not admin', async function () {
      const { token, agent1, anyone } = await fixture();
      await expect(token.connect(anyone).removeAgent(agent1))
        .to.be.revertedWithCustomError(token, 'AccessControlUnauthorizedAccount')
        .withArgs(anyone.address, adminRole);
    });
  });

  describe('ERC7984Restricted', async function () {
    it('should block & unblock', async function () {
      const { token, agent1, recipient } = await fixture();
      await expect(token.isUserAllowed(recipient)).to.eventually.be.true;
      await token.connect(agent1).blockUser(recipient);
      await expect(token.isUserAllowed(recipient)).to.eventually.be.false;
      await token.connect(agent1).unblockUser(recipient);
      await expect(token.isUserAllowed(recipient)).to.eventually.be.true;
    });

    for (const arg of [true, false]) {
      it(`should not ${arg ? 'block' : 'unblock'} if not agent`, async function () {
        const { token, anyone } = await fixture();
        await expect(token.connect(anyone)[arg ? 'blockUser' : 'unblockUser'](anyone))
          .to.be.revertedWithCustomError(token, 'AccessControlUnauthorizedAccount')
          .withArgs(anyone.address, agentRole);
      });
    }
  });

  describe('Mintable', async function () {
    for (const withProof of [true, false]) {
      it(`should mint ${withProof ? 'with proof' : ''}`, async function () {
        const { agent1, recipient } = await fixture();
        const { token } = await fixture();
        await token.$_setCompliantTransfer();
        const amount = 100;
        let params = [recipient.address] as unknown as [
          account: AddressLike,
          encryptedAmount: BytesLike,
          inputProof: BytesLike,
        ];
        if (withProof) {
          const { handles, inputProof } = await fhevm
            .createEncryptedInput(await token.getAddress(), agent1.address)
            .add64(amount)
            .encrypt();
          params.push(handles[0], inputProof);
        } else {
          await token.connect(agent1).createEncryptedAmount(amount);
          params.push(await token.connect(agent1).createEncryptedAmount.staticCall(amount));
        }
        const [, , transferredHandle] = await callAndGetResult(
          token
            .connect(agent1)
            [withProof ? 'confidentialMint(address,bytes32,bytes)' : 'confidentialMint(address,bytes32)'](...params),
          transferEventSignature,
        );
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, transferredHandle, await token.getAddress(), recipient),
        ).to.eventually.equal(amount);
        const balanceHandle = await token.confidentialBalanceOf(recipient);
        await token.connect(agent1).getHandleAllowance(balanceHandle, agent1, true);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceHandle, await token.getAddress(), agent1),
        ).to.eventually.equal(amount);
      });
    }

    it('should not mint if not agent', async function () {
      const { token, recipient, anyone } = await fixture();
      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), anyone.address)
        .add64(100)
        .encrypt();
      await token.$_setCompliantTransfer();
      await expect(
        token
          .connect(anyone)
          ['confidentialMint(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(token, 'AccessControlUnauthorizedAccount')
        .withArgs(anyone.address, agentRole);
    });

    it('should not mint if transfer not compliant', async function () {
      const { token, agent1, recipient } = await fixture();
      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), agent1.address)
        .add64(100)
        .encrypt();
      await expect(
        token
          .connect(agent1)
          ['confidentialMint(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(token, 'UncompliantTransfer')
        .withArgs(ethers.ZeroAddress, recipient.address, encryptedInput.handles[0]);
    });

    it('should not mint if paused', async function () {
      const { token, agent1, recipient } = await fixture();
      await token.connect(agent1).pause();
      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), agent1.address)
        .add64(100)
        .encrypt();
      await expect(
        token
          .connect(agent1)
          ['confidentialMint(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof),
      ).to.be.revertedWithCustomError(token, 'EnforcedPause');
    });
  });

  describe('Burnable', async function () {
    for (const withProof of [true, false]) {
      it(`should burn agent ${withProof ? 'with proof' : ''}`, async function () {
        const { agent1, recipient } = await fixture();
        const { token } = await fixture();
        const encryptedInput = await fhevm
          .createEncryptedInput(await token.getAddress(), agent1.address)
          .add64(100)
          .encrypt();
        await token.$_setCompliantTransfer();
        await token
          .connect(agent1)
          ['confidentialMint(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof);
        const balanceBeforeHandle = await token.confidentialBalanceOf(recipient);
        await token.connect(agent1).getHandleAllowance(balanceBeforeHandle, agent1, true);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceBeforeHandle, await token.getAddress(), agent1),
        ).to.eventually.greaterThan(0);
        const amount = 100;
        let params = [recipient.address] as unknown as [
          account: AddressLike,
          encryptedAmount: BytesLike,
          inputProof: BytesLike,
        ];
        if (withProof) {
          const { handles, inputProof } = await fhevm
            .createEncryptedInput(await token.getAddress(), agent1.address)
            .add64(amount)
            .encrypt();
          params.push(handles[0], inputProof);
        } else {
          await token.connect(agent1).createEncryptedAmount(amount);
          params.push(await token.connect(agent1).createEncryptedAmount.staticCall(amount));
        }
        const [, , transferredHandle] = await callAndGetResult(
          token
            .connect(agent1)
            [withProof ? 'confidentialBurn(address,bytes32,bytes)' : 'confidentialBurn(address,bytes32)'](...params),
          transferEventSignature,
        );
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, transferredHandle, await token.getAddress(), recipient),
        ).to.eventually.equal(amount);
        const balanceHandle = await token.confidentialBalanceOf(recipient);
        await token.connect(agent1).getHandleAllowance(balanceHandle, agent1, true);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceHandle, await token.getAddress(), agent1),
        ).to.eventually.equal(0);
      });
    }

    it('should not burn if not agent', async function () {
      const { token, recipient, anyone } = await fixture();
      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), anyone.address)
        .add64(100)
        .encrypt();
      await token.$_setCompliantTransfer();
      await expect(
        token
          .connect(anyone)
          ['confidentialBurn(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(token, 'AccessControlUnauthorizedAccount')
        .withArgs(anyone.address, agentRole);
    });

    it('should not burn if transfer not compliant', async function () {
      const { token, agent1, recipient } = await fixture();
      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), agent1.address)
        .add64(100)
        .encrypt();
      await expect(
        token
          .connect(agent1)
          ['confidentialBurn(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(token, 'UncompliantTransfer')
        .withArgs(recipient.address, ethers.ZeroAddress, encryptedInput.handles[0]);
    });

    it('should not burn if paused', async function () {
      const { token, agent1, recipient } = await fixture();
      await token.connect(agent1).pause();
      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), agent1.address)
        .add64(100)
        .encrypt();
      await expect(
        token
          .connect(agent1)
          ['confidentialBurn(address,bytes32,bytes)'](recipient, encryptedInput.handles[0], encryptedInput.inputProof),
      ).to.be.revertedWithCustomError(token, 'EnforcedPause');
    });
  });

  describe('Force transfer', async function () {
    for (const withProof of [true, false]) {
      it(`should force transfer ${withProof ? 'with proof' : ''}`, async function () {
        const { agent1, recipient, anyone } = await fixture();
        const { token } = await fixture();
        const encryptedMintValueInput = await fhevm
          .createEncryptedInput(await token.getAddress(), agent1.address)
          .add64(100)
          .encrypt();
        await token.$_setCompliantTransfer();
        await token
          .connect(agent1)
          ['confidentialMint(address,bytes32,bytes)'](
            recipient,
            encryptedMintValueInput.handles[0],
            encryptedMintValueInput.inputProof,
          );
        // set frozen (50 available and about to force transfer 25)
        const encryptedFrozenValueInput = await fhevm
          .createEncryptedInput(await token.getAddress(), agent1.address)
          .add64(50)
          .encrypt();
        await token
          .connect(agent1)
          ['setConfidentialFrozen(address,bytes32,bytes)'](
            recipient,
            encryptedFrozenValueInput.handles[0],
            encryptedFrozenValueInput.inputProof,
          );
        await token.$_unsetCompliantTransfer();
        expect(await token.compliantTransfer()).to.be.false;
        const amount = 25;
        let params = [recipient.address, anyone.address] as unknown as [
          from: AddressLike,
          to: AddressLike,
          encryptedAmount: BytesLike,
          inputProof: BytesLike,
        ];
        if (withProof) {
          const { handles, inputProof } = await fhevm
            .createEncryptedInput(await token.getAddress(), agent1.address)
            .add64(amount)
            .encrypt();
          params.push(handles[0], inputProof);
        } else {
          await token.connect(agent1).createEncryptedAmount(amount);
          params.push(await token.connect(agent1).createEncryptedAmount.staticCall(amount));
        }
        const [from, to, transferredHandle] = await callAndGetResult(
          token
            .connect(agent1)
            [
              withProof
                ? 'forceConfidentialTransferFrom(address,address,bytes32,bytes)'
                : 'forceConfidentialTransferFrom(address,address,bytes32)'
            ](...params),
          transferEventSignature,
        );
        expect(from).equal(recipient.address);
        expect(to).equal(anyone.address);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, transferredHandle, await token.getAddress(), anyone),
        ).to.eventually.equal(amount);
        const balanceHandle = await token.confidentialBalanceOf(recipient);
        await token.connect(agent1).getHandleAllowance(balanceHandle, agent1, true);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceHandle, await token.getAddress(), agent1),
        ).to.eventually.equal(75);
        const frozenHandle = await token.confidentialFrozen(recipient);
        await token.connect(agent1).getHandleAllowance(frozenHandle, agent1, true);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, frozenHandle, await token.getAddress(), agent1),
        ).to.eventually.equal(50); // frozen is left unchanged
      });
    }

    for (const withProof of [true, false]) {
      it(`should force transfer even if frozen ${withProof ? 'with proof' : ''}`, async function () {
        const { agent1, recipient, anyone } = await fixture();
        const { token } = await fixture();
        const encryptedMintValueInput = await fhevm
          .createEncryptedInput(await token.getAddress(), agent1.address)
          .add64(100)
          .encrypt();
        await token.$_setCompliantTransfer();
        await token
          .connect(agent1)
          ['confidentialMint(address,bytes32,bytes)'](
            recipient,
            encryptedMintValueInput.handles[0],
            encryptedMintValueInput.inputProof,
          );
        // set frozen (only 20 available but about to force transfer 25)
        const encryptedFrozenValueInput = await fhevm
          .createEncryptedInput(await token.getAddress(), agent1.address)
          .add64(80)
          .encrypt();
        await token
          .connect(agent1)
          ['setConfidentialFrozen(address,bytes32,bytes)'](
            recipient,
            encryptedFrozenValueInput.handles[0],
            encryptedFrozenValueInput.inputProof,
          );
        // should force transfer even if not compliant
        await token.$_unsetCompliantTransfer();
        expect(await token.compliantTransfer()).to.be.false;
        // should force transfer even if paused
        await token.connect(agent1).pause();
        expect(await token.paused()).to.be.true;
        const amount = 25;
        let params = [recipient.address, anyone.address] as unknown as [
          from: AddressLike,
          to: AddressLike,
          encryptedAmount: BytesLike,
          inputProof: BytesLike,
        ];
        if (withProof) {
          const { handles, inputProof } = await fhevm
            .createEncryptedInput(await token.getAddress(), agent1.address)
            .add64(amount)
            .encrypt();
          params.push(handles[0], inputProof);
        } else {
          await token.connect(agent1).createEncryptedAmount(amount);
          params.push(await token.connect(agent1).createEncryptedAmount.staticCall(amount));
        }
        const [account, frozenAmountHandle] = await callAndGetResult(
          token
            .connect(agent1)
            [
              withProof
                ? 'forceConfidentialTransferFrom(address,address,bytes32,bytes)'
                : 'forceConfidentialTransferFrom(address,address,bytes32)'
            ](...params),
          frozenEventSignature,
        );
        expect(account).equal(recipient.address);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, frozenAmountHandle, await token.getAddress(), recipient),
        ).to.eventually.equal(75);
        const balanceHandle = await token.confidentialBalanceOf(recipient);
        await token.connect(agent1).getHandleAllowance(balanceHandle, agent1, true);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceHandle, await token.getAddress(), agent1),
        ).to.eventually.equal(75);
        const frozenHandle = await token.confidentialFrozen(recipient);
        await token.connect(agent1).getHandleAllowance(frozenHandle, agent1, true);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, frozenHandle, await token.getAddress(), agent1),
        ).to.eventually.equal(75); // frozen got reset to balance
      });
    }

    for (const withProof of [true, false]) {
      it(`should not force transfer if not agent ${withProof ? 'with proof' : ''}`, async function () {
        const { token, recipient, anyone } = await fixture();
        let params = [recipient.address, anyone.address] as unknown as [
          from: AddressLike,
          to: AddressLike,
          encryptedAmount: BytesLike,
          inputProof: BytesLike,
        ];
        const amount = 100;
        if (withProof) {
          const { handles, inputProof } = await fhevm
            .createEncryptedInput(await token.getAddress(), anyone.address)
            .add64(amount)
            .encrypt();
          params.push(handles[0], inputProof);
        } else {
          await token.connect(anyone).createEncryptedAmount(amount);
          params.push(await token.connect(anyone).createEncryptedAmount.staticCall(amount));
        }
        await expect(
          token
            .connect(anyone)
            [
              withProof
                ? 'forceConfidentialTransferFrom(address,address,bytes32,bytes)'
                : 'forceConfidentialTransferFrom(address,address,bytes32)'
            ](...params),
        )
          .to.be.revertedWithCustomError(token, 'AccessControlUnauthorizedAccount')
          .withArgs(anyone.address, agentRole);
      });
    }

    for (const withProof of [true, false]) {
      it(`should not force transfer if receiver blocked ${withProof ? 'with proof' : ''}`, async function () {
        const { token, agent1, recipient, anyone } = await fixture();
        let params = [recipient.address, anyone.address] as unknown as [
          from: AddressLike,
          to: AddressLike,
          encryptedAmount: BytesLike,
          inputProof: BytesLike,
        ];
        const amount = 100;
        if (withProof) {
          const { handles, inputProof } = await fhevm
            .createEncryptedInput(await token.getAddress(), agent1.address)
            .add64(amount)
            .encrypt();
          params.push(handles[0], inputProof);
        } else {
          await token.connect(agent1).createEncryptedAmount(amount);
          params.push(await token.connect(agent1).createEncryptedAmount.staticCall(amount));
        }
        await token.connect(agent1).blockUser(anyone);
        await expect(
          token
            .connect(agent1)
            [
              withProof
                ? 'forceConfidentialTransferFrom(address,address,bytes32,bytes)'
                : 'forceConfidentialTransferFrom(address,address,bytes32)'
            ](...params),
        )
          .to.be.revertedWithCustomError(token, 'UserRestricted')
          .withArgs(anyone.address);
      });
    }
  });

  describe('Transfer', async function () {
    it('should transfer', async function () {
      const { token, agent1, recipient, anyone } = await fixture();
      const encryptedMintValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), agent1.address)
        .add64(100)
        .encrypt();
      await token.$_setCompliantTransfer();
      await token
        .connect(agent1)
        ['confidentialMint(address,bytes32,bytes)'](
          recipient,
          encryptedMintValueInput.handles[0],
          encryptedMintValueInput.inputProof,
        );
      // set frozen (50 available and about to transfer 25)
      const encryptedFrozenValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), agent1.address)
        .add64(50)
        .encrypt();
      await token
        .connect(agent1)
        ['setConfidentialFrozen(address,bytes32,bytes)'](
          recipient,
          encryptedFrozenValueInput.handles[0],
          encryptedFrozenValueInput.inputProof,
        );
      const amount = 25;
      const encryptedTransferValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), recipient.address)
        .add64(amount)
        .encrypt();
      await token.$_setCompliantTransfer();
      expect(await token.compliantTransfer()).to.be.true;
      const [from, to, transferredHandle] = await callAndGetResult(
        token
          .connect(recipient)
          ['confidentialTransfer(address,bytes32,bytes)'](
            anyone,
            encryptedTransferValueInput.handles[0],
            encryptedTransferValueInput.inputProof,
          ),
        transferEventSignature,
      );
      expect(from).equal(recipient.address);
      expect(to).equal(anyone.address);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferredHandle, await token.getAddress(), anyone),
      ).to.eventually.equal(amount);
      await expect(
        fhevm.userDecryptEuint(
          FhevmType.euint64,
          await token.confidentialBalanceOf(anyone),
          await token.getAddress(),
          anyone,
        ),
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

    it('should not transfer if paused', async function () {
      const { token, agent1, recipient, anyone } = await fixture();
      const encryptedTransferValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), recipient.address)
        .add64(25)
        .encrypt();
      await token.connect(agent1).pause();
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
      const { token, recipient, anyone } = await fixture();
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
        .withArgs(recipient.address, anyone.address, encryptedTransferValueInput.handles[0]);
    });

    it('should not transfer if frozen', async function () {
      const { token, agent1, recipient, anyone } = await fixture();
      const encryptedMintValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), agent1.address)
        .add64(100)
        .encrypt();
      await token.$_setCompliantTransfer();
      await token
        .connect(agent1)
        ['confidentialMint(address,bytes32,bytes)'](
          recipient,
          encryptedMintValueInput.handles[0],
          encryptedMintValueInput.inputProof,
        );
      // set frozen (20 available but about to transfer 25)
      const encryptedFrozenValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), agent1.address)
        .add64(80)
        .encrypt();
      await token
        .connect(agent1)
        ['setConfidentialFrozen(address,bytes32,bytes)'](
          recipient,
          encryptedFrozenValueInput.handles[0],
          encryptedFrozenValueInput.inputProof,
        );
      const encryptedTransferValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), recipient.address)
        .add64(25)
        .encrypt();
      await token.$_setCompliantTransfer();
      expect(await token.compliantTransfer()).to.be.true;
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
        fhevm.userDecryptEuint(FhevmType.euint64, transferredHandle, await token.getAddress(), anyone),
      ).to.eventually.equal(0);
      // Balance is unchanged
      await expect(
        fhevm.userDecryptEuint(
          FhevmType.euint64,
          await token.confidentialBalanceOf(recipient),
          await token.getAddress(),
          recipient,
        ),
      ).to.eventually.equal(100);
    });

    for (const arg of [true, false]) {
      it(`should not transfer if ${arg ? 'sender' : 'receiver'} blocked `, async function () {
        const { token, agent1, recipient, anyone } = await fixture();
        const account = arg ? recipient : anyone;
        await token.$_setCompliantTransfer();
        const encryptedInput = await fhevm
          .createEncryptedInput(await token.getAddress(), recipient.address)
          .add64(25)
          .encrypt();
        await token.connect(agent1).blockUser(account);

        await expect(
          token
            .connect(recipient)
            ['confidentialTransfer(address,bytes32,bytes)'](
              anyone,
              encryptedInput.handles[0],
              encryptedInput.inputProof,
            ),
        )
          .to.be.revertedWithCustomError(token, 'UserRestricted')
          .withArgs(account);
      });
    }
  });
});
