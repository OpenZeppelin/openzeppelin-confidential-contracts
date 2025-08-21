import { IACL__factory } from '../../../../types';
import { ACL_ADDRESS } from '../../../helpers/accounts';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

describe('ERC7984Freezable', function () {
  async function deployFixture() {
    const [holder, recipient, freezer, operator, anyone] = await ethers.getSigners();
    const token = await ethers.deployContract('ERC7984FreezableMock', ['name', 'symbol', 'uri', freezer.address]);
    const acl = IACL__factory.connect(ACL_ADDRESS, ethers.provider);
    return { token, acl, holder, recipient, freezer, operator, anyone };
  }

  it('should set and get confidential frozen', async function () {
    const { token, acl, holder, recipient, freezer } = await deployFixture();
    await token.connect(holder).$_mint(recipient.address, 1000);
    const encryptedInput = await fhevm
      .createEncryptedInput(await token.getAddress(), freezer.address)
      .add64(100)
      .encrypt();
    await expect(
      token
        .connect(freezer)
        ['setConfidentialFrozen(address,bytes32,bytes)'](
          recipient.address,
          encryptedInput.handles[0],
          encryptedInput.inputProof,
        ),
    )
      .to.emit(token, 'TokensFrozen')
      .withArgs(recipient.address, encryptedInput.handles[0]);
    const frozenHandle = await token.confidentialFrozen(recipient.address);
    expect(frozenHandle).to.equal(ethers.hexlify(encryptedInput.handles[0]));
    await expect(acl.isAllowed(frozenHandle, recipient.address)).to.eventually.be.true;
    await expect(
      fhevm.userDecryptEuint(FhevmType.euint64, frozenHandle, await token.getAddress(), recipient),
    ).to.eventually.equal(100);
    const balanceHandle = await token.confidentialBalanceOf(recipient.address);
    await expect(
      fhevm.userDecryptEuint(FhevmType.euint64, balanceHandle, await token.getAddress(), recipient),
    ).to.eventually.equal(1000);
    const confidentialAvailableArgs = recipient.address;
    const availableHandle = await token.confidentialAvailable.staticCall(confidentialAvailableArgs);
    await (token as any).connect(recipient).confidentialAvailableAccess(confidentialAvailableArgs);
    await expect(
      fhevm.userDecryptEuint(FhevmType.euint64, availableHandle, await token.getAddress(), recipient),
    ).to.eventually.equal(900);
  });

  it('should not set confidential frozen if not called by freezer', async function () {
    const { token, holder, recipient, anyone } = await deployFixture();
    await token.$_mint(holder.address, 1000).then(tx => tx.wait());
    const encryptedInput = await fhevm
      .createEncryptedInput(await token.getAddress(), anyone.address)
      .add64(100)
      .encrypt();

    await expect(
      token
        .connect(anyone)
        ['setConfidentialFrozen(address,bytes32,bytes)'](
          recipient.address,
          encryptedInput.handles[0],
          encryptedInput.inputProof,
        ),
    )
      .to.be.revertedWithCustomError(token, 'AccessControlUnauthorizedAccount')
      .withArgs(anyone.address, ethers.id('FREEZER_ROLE'));
  });

  it('should transfer max available', async function () {
    const { token, holder, recipient, freezer, anyone } = await deployFixture();
    await token.connect(holder).$_mint(recipient.address, 1000);
    const encryptedInput = await fhevm
      .createEncryptedInput(await token.getAddress(), freezer.address)
      .add64(100)
      .encrypt();
    await token
      .connect(freezer)
      ['setConfidentialFrozen(address,bytes32,bytes)'](
        recipient.address,
        encryptedInput.handles[0],
        encryptedInput.inputProof,
      );
    const confidentialAvailableArgs = recipient.address;
    const availableHandle = await token.confidentialAvailable.staticCall(confidentialAvailableArgs);
    await (token as any).connect(recipient).confidentialAvailableAccess(confidentialAvailableArgs);
    await expect(
      fhevm.userDecryptEuint(FhevmType.euint64, availableHandle, await token.getAddress(), recipient),
    ).to.eventually.equal(900);
    const encryptedInput2 = await fhevm
      .createEncryptedInput(await token.getAddress(), recipient.address)
      .add64(900)
      .encrypt();
    await token
      .connect(recipient)
      ['confidentialTransfer(address,bytes32,bytes)'](
        anyone.address,
        encryptedInput2.handles[0],
        encryptedInput2.inputProof,
      );
    await expect(
      fhevm.userDecryptEuint(
        FhevmType.euint64,
        await token.confidentialBalanceOf(recipient.address),
        await token.getAddress(),
        recipient,
      ),
    ).to.eventually.equal(100);
  });

  it('should transfer zero if transferring more than available', async function () {
    const { token, holder, recipient, freezer, anyone } = await deployFixture();
    await token
      .connect(holder)
      .$_mint(recipient.address, 1000)
      .then(tx => tx.wait());
    const encryptedInput = await fhevm
      .createEncryptedInput(await token.getAddress(), freezer.address)
      .add64(500)
      .encrypt();
    await token
      .connect(freezer)
      ['setConfidentialFrozen(address,bytes32,bytes)'](
        recipient.address,
        encryptedInput.handles[0],
        encryptedInput.inputProof,
      );
    const encryptedInput2 = await fhevm
      .createEncryptedInput(await token.getAddress(), recipient.address)
      .add64(501)
      .encrypt();
    await token
      .connect(recipient)
      ['confidentialTransfer(address,bytes32,bytes)'](
        anyone.address,
        encryptedInput2.handles[0],
        encryptedInput2.inputProof,
      );
    await expect(
      fhevm.userDecryptEuint(
        FhevmType.euint64,
        await token.confidentialBalanceOf(recipient.address),
        await token.getAddress(),
        recipient,
      ),
    ).to.eventually.equal(1000);
  });
});
