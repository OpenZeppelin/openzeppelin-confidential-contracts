import { IACL__factory } from '../../../../types';
import { $ERC7984FreezableMock } from '../../../../types/contracts-exposed/mocks/token/ERC7984FreezableMock.sol/$ERC7984FreezableMock';
import { getAclAddress } from '../../../helpers/accounts';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { AddressLike, BytesLike, EventLog } from 'ethers';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

describe('ERC7984Freezable', function () {
  async function deployFixture() {
    const [holder, recipient, freezer, operator, anyone] = await ethers.getSigners();
    const token = (await ethers.deployContract('$ERC7984FreezableMock', [
      name,
      symbol,
      uri,
    ])) as any as $ERC7984FreezableMock;
    const acl = IACL__factory.connect(await getAclAddress(), ethers.provider);
    return { token, acl, holder, recipient, freezer, operator, anyone };
  }

  it(`should set and get confidential frozen`, async function () {
    const { token, acl, holder, recipient, freezer } = await deployFixture();
    const encryptedRecipientMintInput = await fhevm
      .createEncryptedInput(await token.getAddress(), holder.address)
      .add64(1000)
      .encrypt();
    await token
      .connect(holder)
      ['$_mint(address,bytes32,bytes)'](
        recipient.address,
        encryptedRecipientMintInput.handles[0],
        encryptedRecipientMintInput.inputProof,
      );

    const amount = 100;
    const { handles, inputProof } = await fhevm
      .createEncryptedInput(await token.getAddress(), freezer.address)
      .add64(amount)
      .encrypt();

    let params = [recipient.address, handles[0], inputProof] as unknown as [
      account: AddressLike,
      encryptedAmount: BytesLike,
      inputProof: BytesLike,
    ];

    await expect(token.connect(freezer)['$_setConfidentialFrozen(address,bytes32,bytes)'](...params))
      .to.emit(token, 'TokensFrozen')
      .withArgs(recipient.address, params[1]);

    const frozenHandle = await token.confidentialFrozen(recipient.address);
    expect(frozenHandle).to.equal(ethers.hexlify(params[1]));
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

  it('should transfer max available', async function () {
    const { token, holder, recipient, freezer, anyone } = await deployFixture();
    const encryptedRecipientMintInput = await fhevm
      .createEncryptedInput(await token.getAddress(), holder.address)
      .add64(1000)
      .encrypt();
    await token
      .connect(holder)
      ['$_mint(address,bytes32,bytes)'](
        recipient.address,
        encryptedRecipientMintInput.handles[0],
        encryptedRecipientMintInput.inputProof,
      );
    const encryptedInput = await fhevm
      .createEncryptedInput(await token.getAddress(), freezer.address)
      .add64(100)
      .encrypt();
    await token
      .connect(freezer)
      ['$_setConfidentialFrozen(address,bytes32,bytes)'](
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
    const encryptedRecipientMintInput = await fhevm
      .createEncryptedInput(await token.getAddress(), holder.address)
      .add64(1000)
      .encrypt();
    await token
      .connect(holder)
      ['$_mint(address,bytes32,bytes)'](
        recipient.address,
        encryptedRecipientMintInput.handles[0],
        encryptedRecipientMintInput.inputProof,
      );
    const encryptedInput = await fhevm
      .createEncryptedInput(await token.getAddress(), freezer.address)
      .add64(500)
      .encrypt();
    await token
      .connect(freezer)
      ['$_setConfidentialFrozen(address,bytes32,bytes)'](
        recipient.address,
        encryptedInput.handles[0],
        encryptedInput.inputProof,
      );
    const encryptedInput2 = await fhevm
      .createEncryptedInput(await token.getAddress(), recipient.address)
      .add64(501)
      .encrypt();
    const tx = await token
      .connect(recipient)
      ['confidentialTransfer(address,bytes32,bytes)'](
        anyone.address,
        encryptedInput2.handles[0],
        encryptedInput2.inputProof,
      );
    await expect(tx).to.emit(token, 'ConfidentialTransfer');
    const transferEvent = (await tx
      .wait()
      .then(receipt => receipt!.logs.filter((log: any) => log.address === token.target)[0])) as EventLog;
    expect(transferEvent.args[0]).to.equal(recipient.address);
    expect(transferEvent.args[1]).to.equal(anyone.address);
    await expect(
      fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], await token.getAddress(), recipient),
    ).to.eventually.equal(0);
    // recipient balance is unchanged
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
