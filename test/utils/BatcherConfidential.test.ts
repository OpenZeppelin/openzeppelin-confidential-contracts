import { ERC7984ERC20WrapperMock } from '../../types';
import { $ERC20Mock } from '../../types/contracts-exposed/mocks/token/ERC20Mock.sol/$ERC20Mock';
import { $ERC7984ERC20Wrapper } from '../../types/contracts-exposed/token/ERC7984/extensions/ERC7984ERC20Wrapper.sol/$ERC7984ERC20Wrapper';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';
const wrapAmount = BigInt(ethers.parseEther('1'));
const exchangeRateMantissa = 1_000_000n; // 1e6

describe('BatcherConfidential', function () {
  beforeEach(async function () {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const fromTokenUnderlying = (await ethers.deployContract('$ERC20Mock', [name, symbol, 18])) as any as $ERC20Mock;
    const toTokenUnderlying = (await ethers.deployContract('$ERC20Mock', [name, symbol, 18])) as any as $ERC20Mock;

    const fromToken = (await ethers.deployContract('$ERC7984ERC20WrapperMock', [
      fromTokenUnderlying,
      name,
      symbol,
      uri,
    ])) as any as $ERC7984ERC20Wrapper;
    const toToken = (await ethers.deployContract('$ERC7984ERC20WrapperMock', [
      toTokenUnderlying,
      name,
      symbol,
      uri,
    ])) as any as $ERC7984ERC20Wrapper;

    for (const { to, tokens } of [holder, recipient].flatMap(x =>
      [
        { underlying: fromTokenUnderlying, wrapper: fromToken },
        { underlying: toTokenUnderlying, wrapper: toToken },
      ].map(y => {
        return { to: x, tokens: y };
      }),
    )) {
      await tokens.underlying.$_mint(to, wrapAmount);
      await tokens.underlying.connect(to).approve(tokens.wrapper, wrapAmount);
      await tokens.wrapper.connect(to).wrap(to, wrapAmount);
    }

    Object.assign(this, {
      fromTokenUnderlying,
      toTokenUnderlying,
      fromToken,
      toToken,
      accounts: accounts.slice(3),
      holder,
      recipient,
      operator,
      fromTokenRate: BigInt(await fromToken.rate()),
      toTokenRate: BigInt(await toToken.rate()),
    });
  });

  describe('route via exchange', async function () {
    beforeEach(async function () {
      const exchange = await ethers.deployContract('$ExchangeMock', [
        this.fromTokenUnderlying,
        this.toTokenUnderlying,
        ethers.parseEther('1'),
      ]);

      await Promise.all(
        [this.fromTokenUnderlying, this.toTokenUnderlying].map(async token => {
          await token.$_mint(exchange, ethers.parseEther('1000'));
        }),
      );

      const batcher = await ethers.deployContract('$BatcherConfidentialSwapMock', [
        this.fromToken,
        this.toToken,
        exchange,
        this.operator,
      ]);

      for (const approver of [this.holder, this.recipient]) {
        await this.fromToken.connect(approver).setOperator(batcher, 2n ** 48n - 1n);
      }

      this.batcher = batcher;
    });

    describe('join', async function () {
      it('should increase individual deposits', async function () {
        const batchId = await this.batcher.currentBatchId();

        await expect(this.batcher.deposits(batchId, this.holder)).to.eventually.eq(ethers.ZeroHash);

        await this.batcher.join(1000);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.deposits(batchId, this.holder),
            this.batcher,
            this.holder,
          ),
        ).to.eventually.eq('1000');

        await this.batcher.join(2000);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.deposits(batchId, this.holder),
            this.batcher,
            this.holder,
          ),
        ).to.eventually.eq('3000');
      });

      it('should increase total deposits', async function () {
        const batchId = await this.batcher.currentBatchId();

        await this.batcher.join(1000);
        await this.batcher.connect(this.recipient).join(2000);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.totalDeposits(batchId),
            this.batcher,
            this.operator,
          ),
        ).to.eventually.eq('3000');
      });

      it('should not credit failed transaction', async function () {
        const batchId = await this.batcher.currentBatchId();

        await this.batcher.join(wrapAmount / this.fromTokenRate + 1n);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.deposits(batchId, this.holder),
            this.batcher,
            this.holder,
          ),
        ).to.eventually.eq(0);
      });
    });

    describe('claim', function () {
      beforeEach(async function () {
        this.batchId = await this.batcher.currentBatchId();

        await this.batcher.join(1000);
        await this.batcher.connect(this.holder).dispatchBatch();

        const [, amount] = (await this.fromToken.queryFilter(this.fromToken.filters.UnwrapRequested()))[0].args;
        const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([amount]);
        await this.batcher.dispatchBatchCallback(this.batchId, abiEncodedClearValues, decryptionProof);

        this.exchangeRate = BigInt(await this.batcher.exchangeRate(this.batchId));
        this.deposit = 1000n;
      });

      it('should clear deposits', async function () {
        await this.batcher.claim(this.batchId);
        await expect(this.batcher.deposits(this.batchId, this.holder)).to.eventually.eq(ethers.ZeroHash);
      });

      it('should transfer out correct amount of toToken', async function () {
        const beforeBalanceToTokens = await fhevm.userDecryptEuint(
          FhevmType.euint64,
          await this.toToken.confidentialBalanceOf(this.holder),
          this.toToken,
          this.holder,
        );

        await this.batcher.claim(this.batchId);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.toToken.confidentialBalanceOf(this.holder),
            this.toToken,
            this.holder,
          ),
        ).to.eventually.eq(
          BigInt(beforeBalanceToTokens) + BigInt(this.exchangeRate * this.deposit) / exchangeRateMantissa,
        );
      });

      it('should revert if not finalized', async function () {
        await expect(this.batcher.claim(await this.batcher.currentBatchId())).to.be.revertedWithCustomError(
          this.batcher,
          'BatchNotFinalized',
        );
      });
    });

    describe('cancel', function () {
      beforeEach(async function () {
        this.batchId = await this.batcher.currentBatchId();
        this.deposit = 1000n;

        await this.batcher.join(this.deposit);
      });

      it('should send back full deposit', async function () {
        const beforeBalance = await fhevm.userDecryptEuint(
          FhevmType.euint64,
          await this.fromToken.confidentialBalanceOf(this.holder),
          this.fromToken,
          this.holder,
        );

        await this.batcher.cancel(this.batchId);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.fromToken.confidentialBalanceOf(this.holder),
            this.fromToken,
            this.holder,
          ),
        ).to.eventually.eq(beforeBalance + this.deposit);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.deposits(this.batchId, this.holder),
            this.batcher,
            this.holder,
          ),
        ).to.eventually.eq(0);
      });

      it('should decrease total deposits', async function () {
        await this.batcher.cancel(this.batchId);

        await expect(
          fhevm.userDecryptEuint(
            FhevmType.euint64,
            await this.batcher.totalDeposits(this.batchId),
            this.batcher,
            this.operator,
          ),
        ).to.eventually.eq(0);
      });

      it('should fail if batch already dispatched', async function () {
        await this.batcher.connect(this.holder).dispatchBatch();

        await expect(this.batcher.cancel(this.batchId))
          .to.be.revertedWithCustomError(this.batcher, 'BatchDispatched')
          .withArgs(this.batchId);
      });
    });

    it('happy path', async function () {
      await this.batcher.connect(this.holder).join(1000);
      await this.batcher.connect(this.holder).dispatchBatch();

      const [, amount] = (await this.fromToken.queryFilter(this.fromToken.filters.UnwrapRequested()))[0].args;
      const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([amount]);

      await this.batcher.dispatchBatchCallback(1, abiEncodedClearValues, decryptionProof);

      const exchangeRate = BigInt(await this.batcher.exchangeRate(1));
      expect(exchangeRate).to.eq(exchangeRateMantissa);

      await this.batcher.connect(this.holder).claim(1);

      await expect(
        fhevm.userDecryptEuint(
          FhevmType.euint64,
          await this.fromToken.confidentialBalanceOf(this.holder),
          this.fromToken,
          this.holder,
        ),
      ).to.eventually.eq(wrapAmount / this.fromTokenRate - 1000n);

      await expect(
        fhevm.userDecryptEuint(
          FhevmType.euint64,
          await this.toToken.confidentialBalanceOf(this.holder),
          this.toToken,
          this.holder,
        ),
      ).to.eventually.eq(wrapAmount / this.toTokenRate + (1000n * exchangeRate) / exchangeRateMantissa);
    });

    it('unwrap already finalized', async function () {
      await this.batcher.connect(this.holder).join(1000);
      await this.batcher.connect(this.holder).dispatchBatch();

      await publicDecryptAndFinalizeUnwrap(this.fromToken, this.holder);

      const [, amount] = (await this.fromToken.queryFilter(this.fromToken.filters.UnwrapRequested()))[0].args;
      const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([amount]);

      await this.batcher.dispatchBatchCallback(1, abiEncodedClearValues, decryptionProof);
      await this.batcher.connect(this.holder).claim(1);

      const exchangeRate = BigInt(await this.batcher.exchangeRate(1));
      await expect(
        fhevm.userDecryptEuint(
          FhevmType.euint64,
          await this.toToken.confidentialBalanceOf(this.holder),
          this.toToken,
          this.holder,
        ),
      ).to.eventually.eq(wrapAmount / this.toTokenRate + (1000n * exchangeRate) / exchangeRateMantissa);
    });

    it('unwrap already finalized, invalid callback value', async function () {
      await this.batcher.connect(this.holder).join(1000);
      await this.batcher.connect(this.holder).dispatchBatch();

      await publicDecryptAndFinalizeUnwrap(this.fromToken, this.holder);

      const [, amount] = (await this.fromToken.queryFilter(this.fromToken.filters.UnwrapRequested()))[0].args;
      const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([amount]);

      await expect(this.batcher.dispatchBatchCallback(1, BigInt(abiEncodedClearValues) + 1n, decryptionProof)).to.be
        .reverted;
    });
  });
});

async function publicDecryptAndFinalizeUnwrap(wrapper: ERC7984ERC20WrapperMock, caller: HardhatEthersSigner) {
  const [to, amount] = (await wrapper.queryFilter(wrapper.filters.UnwrapRequested()))[0].args;
  const { abiEncodedClearValues, decryptionProof } = await fhevm.publicDecrypt([amount]);
  await expect(wrapper.connect(caller).finalizeUnwrap(amount, abiEncodedClearValues, decryptionProof))
    .to.emit(wrapper, 'UnwrapFinalized')
    .withArgs(to, amount, abiEncodedClearValues);
}
