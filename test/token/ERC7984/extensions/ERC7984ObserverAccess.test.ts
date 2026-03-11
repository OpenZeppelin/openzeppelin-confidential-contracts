import { FhevmType } from '@fhevm/hardhat-plugin';
import { mine } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'Observer Access Token';
const symbol = 'OAT';
const uri = 'https://example.com/metadata';

describe('ERC7984ObserverAccess', function () {
  beforeEach(async function () {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const token = await ethers.deployContract('$ERC7984ObserverAccessMock', [name, symbol, uri]);
    this.holder = holder;
    this.recipient = recipient;
    this.token = token;
    this.operator = operator;

    const encryptedInput = await fhevm
      .createEncryptedInput(this.token.target, this.holder.address)
      .add64(1000)
      .encrypt();

    await this.token
      .connect(this.holder)
      ['$_mint(address,bytes32,bytes)'](this.holder, encryptedInput.handles[0], encryptedInput.inputProof);
  });

  it('should be able to set an observer from holder', async function () {
    const observer = this.operator;

    await expect(this.token.connect(this.holder).setObserver(this.holder, observer))
      .to.emit(this.token, 'ERC7984ObserverAccessObserverSet')
      .withArgs(this.holder.address, ethers.ZeroAddress, observer.address);
    await expect(this.token.observer(this.holder)).to.eventually.equal(observer.address);
  });

  it('setting observer to existing observer should be a noop', async function () {
    const observer = this.operator;
    await this.token.connect(this.holder).setObserver(this.holder, observer);

    await expect(this.token.connect(this.holder).setObserver(this.holder, observer)).to.not.emit(
      this.token,
      'ERC7984ObserverAccessObserverSet',
    );
  });

  it('should not be able to set a observer from non-holder', async function () {
    const observer = this.operator;
    await expect(this.token.connect(this.recipient).setObserver(this.holder, observer))
      .to.be.revertedWithCustomError(this.token, 'Unauthorized')
      .withArgs();
  });

  it('observer should be able to set an observer to zero address', async function () {
    const observer = this.operator;

    await expect(this.token.connect(this.holder).setObserver(this.holder, observer));
    await expect(this.token.connect(observer).setObserver(this.holder, ethers.ZeroAddress))
      .to.emit(this.token, 'ERC7984ObserverAccessObserverSet')
      .withArgs(this.holder.address, observer.address, ethers.ZeroAddress);
    await expect(this.token.observer(this.holder)).to.eventually.equal(ethers.ZeroAddress);
  });

  describe('reencrypt', function () {
    for (const sender of [true, false]) {
      it(`${sender ? 'sender' : 'recipient'} observer should be able to reencrypt transfer amounts`, async function () {
        const observer = this.operator;

        const observed = sender ? this.holder : this.recipient;
        await expect(this.token.connect(observed).setObserver(observed, observer))
          .to.emit(this.token, 'ERC7984ObserverAccessObserverSet')
          .withArgs(observed.address, ethers.ZeroAddress, observer.address);

        const encryptedInput = await fhevm
          .createEncryptedInput(this.token.target, this.holder.address)
          .add64(100)
          .encrypt();

        const tx = await this.token
          .connect(this.holder)
          ['confidentialTransfer(address,bytes32,bytes)'](
            this.recipient,
            encryptedInput.handles[0],
            encryptedInput.inputProof,
          );

        const transferredHandle = await tx
          .wait()
          .then((receipt: any) => receipt.logs.filter((log: any) => log.address === this.token.target)[0].args[2]);

        await mine(1);

        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, transferredHandle, this.token.target, observer),
        ).to.eventually.equal(100);
      });
    }

    it('observer should be able to reencrypt balance', async function () {
      await this.token.connect(this.holder).setObserver(this.holder, this.operator);
      await expect(
        fhevm.userDecryptEuint(
          FhevmType.euint64,
          await this.token.confidentialBalanceOf(this.holder),
          this.token.target,
          this.operator,
        ),
      ).to.eventually.equal(1000);
    });

    it('observer should be able to reencrypt future balance', async function () {
      await this.token.connect(this.holder).setObserver(this.holder, this.operator);

      const encryptedInput = await fhevm
        .createEncryptedInput(this.token.target, this.holder.address)
        .add64(100)
        .encrypt();

      await this.token
        .connect(this.holder)
        ['confidentialTransfer(address,bytes32,bytes)'](
          this.recipient,
          encryptedInput.handles[0],
          encryptedInput.inputProof,
        );

      await expect(
        fhevm.userDecryptEuint(
          FhevmType.euint64,
          await this.token.confidentialBalanceOf(this.holder),
          this.token.target,
          this.operator,
        ),
      ).to.eventually.equal(900);
    });
  });
});
