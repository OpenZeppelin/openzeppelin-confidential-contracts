import { IERC165__factory, IERC7984__factory, IERC7984Rwa__factory } from '../../../../types';
import { callAndGetResult } from '../../../helpers/event';
import { getFunctions, getInterfaceId } from '../../../helpers/interface';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { AddressLike, BytesLike } from 'ethers';
import { ethers, fhevm } from 'hardhat';

const transferEventSignature = 'ConfidentialTransfer(address,address,bytes32)';
const adminRole = ethers.ZeroHash;
const agentRole = ethers.id('AGENT_ROLE');

const fixture = async () => {
  const [admin, agent1, agent2, recipient, anyone] = await ethers.getSigners();
  const token = await ethers.deployContract('ERC7984RwaMock', ['name', 'symbol', 'uri', admin.address]);
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

  describe('ERC7984Freezable', async function () {
    for (let withProof of [false, true]) {
      it(`should set and get confidential frozen ${withProof ? 'with proof' : ''}`, async function () {
        const { token, agent1, recipient } = await fixture();
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
        await expect(
          await token
            .connect(agent1)
            [withProof ? 'setConfidentialFrozen(address,bytes32,bytes)' : 'setConfidentialFrozen(address,bytes32)'](
              ...params,
            ),
        ).to.emit(token, 'TokensFrozen');
        const frozenHandle = await token.confidentialFrozen(recipient.address);
        expect(frozenHandle).to.equal(ethers.hexlify(params[1]));
      });
    }

    for (let withProof of [false, true]) {
      it(`should not set confidential frozen ${withProof ? 'with proof' : ''} if not agent`, async function () {
        const { token, recipient, anyone } = await fixture();
        const amount = 100;
        let params = [recipient.address] as unknown as [
          account: AddressLike,
          encryptedAmount: BytesLike,
          inputProof: BytesLike,
        ];
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
            [withProof ? 'setConfidentialFrozen(address,bytes32,bytes)' : 'setConfidentialFrozen(address,bytes32)'](
              ...params,
            ),
        )
          .to.be.revertedWithCustomError(token, 'AccessControlUnauthorizedAccount')
          .withArgs(anyone.address, agentRole);
      });
    }

    it(`should not set confidential frozen if amount not allowed`, async function () {
      const { token, recipient, agent1, anyone } = await fixture();
      const amount = 200;
      await token.connect(anyone).createEncryptedAmount(amount);
      const encryptedAmount = await token.connect(anyone).createEncryptedAmount.staticCall(amount);
      await expect(token.connect(agent1)['setConfidentialFrozen(address,bytes32)'](recipient.address, encryptedAmount))
        .to.be.revertedWithCustomError(token, 'ERC7984UnauthorizedUseOfEncryptedAmount')
        .withArgs(encryptedAmount, agent1.address);
    });
  });

  describe('Mintable', async function () {
    for (const withProof of [true, false]) {
      it(`should mint ${withProof ? 'with proof' : ''}`, async function () {
        const { agent1, recipient, token } = await fixture();
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

    for (let withProof of [false, true]) {
      it(`should not mint ${withProof ? 'with proof' : ''} if not agent`, async function () {
        const { token, recipient, anyone } = await fixture();
        const amount = 100;
        let params = [recipient.address] as unknown as [
          account: AddressLike,
          encryptedAmount: BytesLike,
          inputProof: BytesLike,
        ];
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
            [withProof ? 'confidentialMint(address,bytes32,bytes)' : 'confidentialMint(address,bytes32)'](...params),
        )
          .to.be.revertedWithCustomError(token, 'AccessControlUnauthorizedAccount')
          .withArgs(anyone.address, agentRole);
      });
    }

    it(`should not mint if amount not allowed`, async function () {
      const { token, recipient, agent1, anyone } = await fixture();
      const amount = 200;
      await token.connect(anyone).createEncryptedAmount(amount);
      const encryptedAmount = await token.connect(anyone).createEncryptedAmount.staticCall(amount);
      await expect(token.connect(agent1)['confidentialMint(address,bytes32)'](recipient.address, encryptedAmount))
        .to.be.revertedWithCustomError(token, 'ERC7984UnauthorizedUseOfEncryptedAmount')
        .withArgs(encryptedAmount, agent1.address);
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
        const { agent1, recipient, token } = await fixture();
        const encryptedInput = await fhevm
          .createEncryptedInput(await token.getAddress(), agent1.address)
          .add64(100)
          .encrypt();
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

    for (let withProof of [false, true]) {
      it(`should not burn ${withProof ? 'with proof' : ''} if not agent`, async function () {
        const { token, recipient, anyone } = await fixture();
        const amount = 100;
        let params = [recipient.address] as unknown as [
          account: AddressLike,
          encryptedAmount: BytesLike,
          inputProof: BytesLike,
        ];
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
            [withProof ? 'confidentialBurn(address,bytes32,bytes)' : 'confidentialBurn(address,bytes32)'](...params),
        )
          .to.be.revertedWithCustomError(token, 'AccessControlUnauthorizedAccount')
          .withArgs(anyone.address, agentRole);
      });
    }

    it(`should not burn if amount not allowed`, async function () {
      const { token, recipient, agent1, anyone } = await fixture();
      const amount = 200;
      await token.connect(anyone).createEncryptedAmount(amount);
      const encryptedAmount = await token.connect(anyone).createEncryptedAmount.staticCall(amount);
      await expect(token.connect(agent1)['confidentialBurn(address,bytes32)'](recipient.address, encryptedAmount))
        .to.be.revertedWithCustomError(token, 'ERC7984UnauthorizedUseOfEncryptedAmount')
        .withArgs(encryptedAmount, agent1.address);
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
      it(`should force transfer${withProof ? ' with proof' : ''}`, async function () {
        const { agent1, recipient, anyone, token } = await fixture();
        await token['$_mint(address,uint64)'](recipient, 100);
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
        await token.connect(agent1).pause();
        await token.connect(agent1).blockUser(recipient);
        const tx = token
          .connect(agent1)
          [
            withProof
              ? 'forceConfidentialTransferFrom(address,address,bytes32,bytes)'
              : 'forceConfidentialTransferFrom(address,address,bytes32)'
          ](...params);
        const [from, to, transferredHandle] = await callAndGetResult(tx, transferEventSignature);
        expect(from).to.equal(recipient.address);
        expect(to).to.equal(anyone.address);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, transferredHandle, await token.getAddress(), anyone),
        ).to.eventually.equal(amount);
        const balanceHandle = await token.confidentialBalanceOf(recipient);
        await token.connect(agent1).getHandleAllowance(balanceHandle, agent1, true);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceHandle, await token.getAddress(), agent1),
        ).to.eventually.equal(75);
      });
    }

    for (const withProof of [true, false]) {
      it(`should not force transfer frozen funds ${withProof ? 'with proof' : ''}`, async function () {
        const { agent1, recipient, anyone, token } = await fixture();
        await token['$_mint(address,uint64)'](recipient, 100);
        // set frozen (only 20 available but about to force transfer 25)
        await token.$_setConfidentialFrozen(recipient, 80);
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
        expect(from).to.equal(recipient.address);
        expect(to).to.equal(anyone.address);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, transferredHandle, await token.getAddress(), recipient),
        ).to.eventually.equal(0);

        const balanceHandle = await token.confidentialBalanceOf(recipient);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceHandle, await token.getAddress(), recipient),
        ).to.eventually.equal(100);

        const frozenHandle = await token.confidentialFrozen(recipient);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, frozenHandle, await token.getAddress(), recipient),
        ).to.eventually.equal(80);
      });
    }

    for (let withProof of [false, true]) {
      it(`should not force transfer ${withProof ? 'with proof' : ''} if not agent`, async function () {
        const { token, recipient, anyone } = await fixture();
        const amount = 100;
        let params = [recipient.address, anyone.address] as unknown as [
          from: AddressLike,
          to: AddressLike,
          encryptedAmount: BytesLike,
          inputProof: BytesLike,
        ];
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

    it('should not force transfer if amount not allowed', async function () {
      const { token, recipient, agent1, anyone } = await fixture();
      const amount = 200;
      await token.connect(anyone).createEncryptedAmount(amount);
      const encryptedAmount = await token.connect(anyone).createEncryptedAmount.staticCall(amount);
      await expect(
        token
          .connect(agent1)
          ['forceConfidentialTransferFrom(address,address,bytes32)'](
            recipient.address,
            anyone.address,
            encryptedAmount,
          ),
      )
        .to.be.revertedWithCustomError(token, 'ERC7984UnauthorizedUseOfEncryptedAmount')
        .withArgs(encryptedAmount, agent1.address);
    });

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
      await token['$_mint(address,uint64)'](recipient, 100);
      // set frozen (50 available and about to transfer 25)
      await token.$_setConfidentialFrozen(recipient, 50);
      const amount = 25;
      const encryptedTransferValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), recipient.address)
        .add64(amount)
        .encrypt();
      const tx = token
        .connect(recipient)
        ['confidentialTransfer(address,bytes32,bytes)'](
          anyone,
          encryptedTransferValueInput.handles[0],
          encryptedTransferValueInput.inputProof,
        );
      const [from, to, transferredHandle] = await callAndGetResult(tx, transferEventSignature);
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

    it('should not transfer if frozen', async function () {
      const { token, agent1, recipient, anyone } = await fixture();
      await token['$_mint(address,uint64)'](recipient, 100);
      // set frozen (20 available but about to transfer 25)
      await token.$_setConfidentialFrozen(recipient, 80);
      const encryptedTransferValueInput = await fhevm
        .createEncryptedInput(await token.getAddress(), recipient.address)
        .add64(25)
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
