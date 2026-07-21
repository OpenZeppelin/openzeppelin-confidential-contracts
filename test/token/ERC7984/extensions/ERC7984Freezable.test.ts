import { IACL__factory } from '../../../../types';
import { getAclAddress } from '../../../helpers/accounts';
import { shouldBehaveLikeERC7984 } from '../ERC7984.behavior';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { AddressLike, BytesLike, EventLog } from 'ethers';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';
const decimals = 6;

describe('ERC7984Freezable', function () {
  beforeEach(async function () {
    const [holder, recipient, freezer, operator, anyone] = await ethers.getSigners();
    const token = await ethers.deployContract('$ERC7984FreezableMock', [name, symbol, uri]);
    const acl = IACL__factory.connect(await getAclAddress(), ethers.provider);

    Object.assign(this, { holder, recipient, freezer, operator, anyone, token, acl });
  });

  it(`should set and get confidential frozen`, async function () {
    const encryptedRecipientMintInput = await fhevm
      .createEncryptedInput(await this.token.getAddress(), this.holder.address)
      .add64(1000)
      .encrypt();
    await this.token
      .connect(this.holder)
      ['$_mint(address,bytes32,bytes)'](
        this.recipient.address,
        encryptedRecipientMintInput.handles[0],
        encryptedRecipientMintInput.inputProof,
      );

    const amount = 100;
    const { handles, inputProof } = await fhevm
      .createEncryptedInput(await this.token.getAddress(), this.freezer.address)
      .add64(amount)
      .encrypt();

    let params = [this.recipient.address, handles[0], inputProof] as unknown as [
      account: AddressLike,
      encryptedAmount: BytesLike,
      inputProof: BytesLike,
    ];

    await expect(this.token.connect(this.freezer)['$_setConfidentialFrozen(address,bytes32,bytes)'](...params))
      .to.emit(this.token, 'TokensFrozen')
      .withArgs(this.recipient.address, params[1]);

    const frozenHandle = await this.token.confidentialFrozen(this.recipient.address);
    expect(frozenHandle).to.equal(ethers.hexlify(params[1]));
    await expect(this.acl.isAllowed(frozenHandle, this.recipient.address)).to.eventually.be.true;
    await expect(
      fhevm.userDecryptEuint(FhevmType.euint64, frozenHandle, await this.token.getAddress(), this.recipient),
    ).to.eventually.equal(100);
    const balanceHandle = await this.token.confidentialBalanceOf(this.recipient.address);
    await expect(
      fhevm.userDecryptEuint(FhevmType.euint64, balanceHandle, await this.token.getAddress(), this.recipient),
    ).to.eventually.equal(1000);
    const confidentialAvailableArgs = this.recipient.address;
    const availableHandle = await this.token.confidentialAvailable.staticCall(confidentialAvailableArgs);
    await (this.token as any).connect(this.recipient).confidentialAvailableAccess(confidentialAvailableArgs);
    await expect(
      fhevm.userDecryptEuint(FhevmType.euint64, availableHandle, await this.token.getAddress(), this.recipient),
    ).to.eventually.equal(900);
  });

  it('should transfer max available', async function () {
    const encryptedRecipientMintInput = await fhevm
      .createEncryptedInput(await this.token.getAddress(), this.holder.address)
      .add64(1000)
      .encrypt();
    await this.token
      .connect(this.holder)
      ['$_mint(address,bytes32,bytes)'](
        this.recipient.address,
        encryptedRecipientMintInput.handles[0],
        encryptedRecipientMintInput.inputProof,
      );
    const encryptedInput = await fhevm
      .createEncryptedInput(await this.token.getAddress(), this.freezer.address)
      .add64(100)
      .encrypt();
    await this.token
      .connect(this.freezer)
      ['$_setConfidentialFrozen(address,bytes32,bytes)'](
        this.recipient.address,
        encryptedInput.handles[0],
        encryptedInput.inputProof,
      );
    const confidentialAvailableArgs = this.recipient.address;
    const availableHandle = await this.token.confidentialAvailable.staticCall(confidentialAvailableArgs);
    await (this.token as any).connect(this.recipient).confidentialAvailableAccess(confidentialAvailableArgs);
    await expect(
      fhevm.userDecryptEuint(FhevmType.euint64, availableHandle, await this.token.getAddress(), this.recipient),
    ).to.eventually.equal(900);
    const encryptedInput2 = await fhevm
      .createEncryptedInput(await this.token.getAddress(), this.recipient.address)
      .add64(900)
      .encrypt();
    await this.token
      .connect(this.recipient)
      ['confidentialTransfer(address,bytes32,bytes)'](
        this.anyone.address,
        encryptedInput2.handles[0],
        encryptedInput2.inputProof,
      );
    await expect(
      fhevm.userDecryptEuint(
        FhevmType.euint64,
        await this.token.confidentialBalanceOf(this.recipient.address),
        await this.token.getAddress(),
        this.recipient,
      ),
    ).to.eventually.equal(100);
  });

  it('should transfer zero if transferring more than available', async function () {
    const encryptedRecipientMintInput = await fhevm
      .createEncryptedInput(await this.token.getAddress(), this.holder.address)
      .add64(1000)
      .encrypt();
    await this.token
      .connect(this.holder)
      ['$_mint(address,bytes32,bytes)'](
        this.recipient.address,
        encryptedRecipientMintInput.handles[0],
        encryptedRecipientMintInput.inputProof,
      );
    const encryptedInput = await fhevm
      .createEncryptedInput(await this.token.getAddress(), this.freezer.address)
      .add64(500)
      .encrypt();
    await this.token
      .connect(this.freezer)
      ['$_setConfidentialFrozen(address,bytes32,bytes)'](
        this.recipient.address,
        encryptedInput.handles[0],
        encryptedInput.inputProof,
      );
    const encryptedInput2 = await fhevm
      .createEncryptedInput(await this.token.getAddress(), this.recipient.address)
      .add64(501)
      .encrypt();
    const tx = await this.token
      .connect(this.recipient)
      ['confidentialTransfer(address,bytes32,bytes)'](
        this.anyone.address,
        encryptedInput2.handles[0],
        encryptedInput2.inputProof,
      );
    await expect(tx).to.emit(this.token, 'ConfidentialTransfer');
    const transferEvent = (await tx
      .wait()
      .then((receipt: any) => receipt!.logs.filter((log: any) => log.address === this.token.target)[0])) as EventLog;
    expect(transferEvent.args[0]).to.equal(this.recipient.address);
    expect(transferEvent.args[1]).to.equal(this.anyone.address);
    await expect(
      fhevm.userDecryptEuint(FhevmType.euint64, transferEvent.args[2], await this.token.getAddress(), this.recipient),
    ).to.eventually.equal(0);
    // recipient balance is unchanged
    await expect(
      fhevm.userDecryptEuint(
        FhevmType.euint64,
        await this.token.confidentialBalanceOf(this.recipient.address),
        await this.token.getAddress(),
        this.recipient,
      ),
    ).to.eventually.equal(1000);
  });

  shouldBehaveLikeERC7984(name, symbol, uri, decimals);
});
