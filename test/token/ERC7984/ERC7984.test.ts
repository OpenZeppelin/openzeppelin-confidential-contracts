import { shouldBehaveLikeERC7984 } from './ERC7984.behavior';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';
const decimals = 6;

describe('ERC7984', function () {
  beforeEach(async function () {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const token = await ethers.deployContract('$ERC7984Mock', [name, symbol, uri]);
    this.accounts = accounts.slice(3);
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

  shouldBehaveLikeERC7984(name, symbol, uri, decimals, { holderInitialBalance: 1000 });

  describe('mint', function () {
    for (const existingUser of [false, true]) {
      it(`to ${existingUser ? 'existing' : 'new'} user`, async function () {
        if (existingUser) {
          const encryptedInput = await fhevm
            .createEncryptedInput(await this.token.getAddress(), this.holder.address)
            .add64(1000)
            .encrypt();

          await this.token
            .connect(this.holder)
            ['$_mint(address,bytes32,bytes)'](this.holder, encryptedInput.handles[0], encryptedInput.inputProof);
        }

        const balanceOfHandleHolder = await this.token.confidentialBalanceOf(this.holder);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, await this.token.getAddress(), this.holder),
        ).to.eventually.equal(existingUser ? 2000 : 1000);

        // Check total supply
        const totalSupplyHandle = await this.token.confidentialTotalSupply();
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, totalSupplyHandle, await this.token.getAddress(), this.holder),
        ).to.eventually.equal(existingUser ? 2000 : 1000);
      });
    }

    it('from zero address', async function () {
      const encryptedInput = await fhevm
        .createEncryptedInput(await this.token.getAddress(), this.holder.address)
        .add64(400)
        .encrypt();

      await expect(
        this.token
          .connect(this.holder)
          ['$_mint(address,bytes32,bytes)'](ethers.ZeroAddress, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidReceiver')
        .withArgs(ethers.ZeroAddress);
    });
  });

  describe('burn', function () {
    for (const sufficientBalance of [false, true]) {
      it(`from a user with ${sufficientBalance ? 'sufficient' : 'insufficient'} balance`, async function () {
        const burnAmount = sufficientBalance ? 400 : 1100;

        const encryptedInput = await fhevm
          .createEncryptedInput(await this.token.getAddress(), this.holder.address)
          .add64(burnAmount)
          .encrypt();

        await this.token
          .connect(this.holder)
          ['$_burn(address,bytes32,bytes)'](this.holder, encryptedInput.handles[0], encryptedInput.inputProof);

        const balanceOfHandleHolder = await this.token.confidentialBalanceOf(this.holder);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, await this.token.getAddress(), this.holder),
        ).to.eventually.equal(sufficientBalance ? 600 : 1000);

        // Check total supply
        const totalSupplyHandle = await this.token.confidentialTotalSupply();
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, totalSupplyHandle, await this.token.getAddress(), this.holder),
        ).to.eventually.equal(sufficientBalance ? 600 : 1000);
      });
    }

    it('from zero address', async function () {
      const encryptedInput = await fhevm
        .createEncryptedInput(await this.token.getAddress(), this.holder.address)
        .add64(400)
        .encrypt();

      await expect(
        this.token
          .connect(this.holder)
          ['$_burn(address,bytes32,bytes)'](ethers.ZeroAddress, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidSender')
        .withArgs(ethers.ZeroAddress);
    });
  });

  describe('disclose', function () {
    beforeEach(async function () {
      this.expectedAmount = undefined;
      this.expectedHandle = undefined;
      this.requester = undefined;
    });

    it('user balance', async function () {
      const holderBalanceHandle = await this.token.confidentialBalanceOf(this.holder);

      await this.token.connect(this.holder).requestDiscloseEncryptedAmount(holderBalanceHandle);

      this.requester = this.holder.address;
      this.expectedAmount = 1000n;
      this.expectedHandle = holderBalanceHandle;
    });

    it('transaction amount', async function () {
      const encryptedInput = await fhevm
        .createEncryptedInput(await this.token.getAddress(), this.holder.address)
        .add64(400)
        .encrypt();

      const tx = await this.token['confidentialTransfer(address,bytes32,bytes)'](
        this.recipient,
        encryptedInput.handles[0],
        encryptedInput.inputProof,
      );

      const transferEvent = (await tx.wait()).logs.filter((log: any) => log.address === this.token.target)[0];
      const transferAmount = transferEvent.args[2];

      await this.token.connect(this.recipient).requestDiscloseEncryptedAmount(transferAmount);

      this.requester = this.recipient.address;
      this.expectedAmount = 400n;
      this.expectedHandle = transferAmount;
    });

    it("other user's balance", async function () {
      const holderBalanceHandle = await this.token.confidentialBalanceOf(this.holder);

      await expect(this.token.connect(this.recipient).requestDiscloseEncryptedAmount(holderBalanceHandle))
        .to.be.revertedWithCustomError(this.token, 'ERC7984UnauthorizedUseOfEncryptedAmount')
        .withArgs(holderBalanceHandle, this.recipient);
    });

    it('invalid signature reverts', async function () {
      const holderBalanceHandle = await this.token.confidentialBalanceOf(this.holder);
      await this.token.connect(this.holder).requestDiscloseEncryptedAmount(holderBalanceHandle);

      await expect(this.token.connect(this.holder).discloseEncryptedAmount(holderBalanceHandle, 0, '0x')).to.be
        .reverted;
    });

    afterEach(async function () {
      if (this.expectedHandle === undefined || this.expectedAmount === undefined) return;

      const amountDiscloseRequestedEvent = (
        await this.token.queryFilter(this.token.filters.AmountDiscloseRequested())
      )[0];

      expect(this.expectedHandle).to.equal(amountDiscloseRequestedEvent.args[0]);
      expect(this.requester).to.equal(amountDiscloseRequestedEvent.args[1]);

      const publicDecryptResults = await fhevm.publicDecrypt([this.expectedHandle]);

      await expect(
        this.token
          .connect(this.holder)
          .discloseEncryptedAmount(
            this.expectedHandle,
            publicDecryptResults.abiEncodedClearValues,
            publicDecryptResults.decryptionProof,
          ),
      )
        .to.emit(this.token, 'AmountDisclosed')
        .withArgs(this.expectedHandle, this.expectedAmount);
    });
  });
});
