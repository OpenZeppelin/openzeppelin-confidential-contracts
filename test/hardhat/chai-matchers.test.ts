import { AssertionError, expect } from 'chai';
import { ethers, network } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

describe('Confidential balance matchers', function () {
  beforeEach(async function () {
    const [holder, recipient, other] = await ethers.getSigners();

    this.holder = holder;
    this.recipient = recipient;
    this.other = other;
    this.token = await ethers.deployContract('$ERC7984Mock', [name, symbol, uri]);

    await this.token['$_mint(address,uint64)'](this.holder, 1000);

    this.transfer = (amount: number) =>
      this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](this.recipient, amount);
  });

  describe('changeConfidentialBalance', function () {
    it('asserts the balance change of each side of a transfer', async function () {
      const tx = this.transfer(100);
      await expect(tx).to.changeConfidentialBalance(this.token, this.holder, -100);
      await expect(tx).to.changeConfidentialBalance(this.token, this.recipient, 100);
    });

    it('treats an uninitialized balance as zero', async function () {
      await expect(this.token.confidentialBalanceOf(this.recipient)).to.eventually.equal(ethers.ZeroHash);
      await expect(this.transfer(100)).to.changeConfidentialBalance(this.token, this.recipient, 100);
    });

    it('asserts no change for an account the transaction does not touch', async function () {
      await expect(this.transfer(100)).to.changeConfidentialBalance(this.token, this.other, 0);
    });

    it('asserts no change when the transfer exceeds the balance', async function () {
      const tx = this.transfer(2000);
      await expect(tx).to.changeConfidentialBalance(this.token, this.holder, 0);
      await expect(tx).to.changeConfidentialBalance(this.token, this.recipient, 0);
    });

    it('accepts a function returning the transaction', async function () {
      await expect(() => this.transfer(100)).to.changeConfidentialBalance(this.token, this.holder, -100);
    });

    it('accepts an address string', async function () {
      await expect(this.transfer(100)).to.changeConfidentialBalance(this.token, this.recipient.address, 100);
    });

    it('accepts a predicate', async function () {
      await expect(this.transfer(100)).to.changeConfidentialBalance(
        this.token,
        this.holder,
        (change: bigint) => change < 0n,
      );
    });

    it('supports negation', async function () {
      await expect(this.transfer(100)).to.not.changeConfidentialBalance(this.token, this.holder, -1);
    });

    it('fails when the balance changes by a different amount', async function () {
      await expect(
        expect(this.transfer(100)).to.changeConfidentialBalance(this.token, this.holder, -1),
      ).to.be.rejectedWith(
        AssertionError,
        `Expected the confidential balance of ${symbol} tokens for "${this.holder.address}" to change by -1, but it changed by -100`,
      );
    });

    it('fails when the balance changes by the amount and the assertion is negated', async function () {
      await expect(
        expect(this.transfer(100)).to.not.changeConfidentialBalance(this.token, this.holder, -100),
      ).to.be.rejectedWith(
        AssertionError,
        `Expected the confidential balance of ${symbol} tokens for "${this.holder.address}" NOT to change by -100, but it did`,
      );
    });

    it('fails when the predicate is not satisfied', async function () {
      await expect(
        expect(this.transfer(100)).to.changeConfidentialBalance(
          this.token,
          this.holder,
          (change: bigint) => change > 0n,
        ),
      ).to.be.rejectedWith(
        AssertionError,
        `Expected the confidential balance of ${symbol} tokens for "${this.holder.address}" to satisfy the predicate, but it didn't (confidential balance change: -100)`,
      );
    });

    it('fails when the predicate is satisfied and the assertion is negated', async function () {
      await expect(
        expect(this.transfer(100)).to.not.changeConfidentialBalance(
          this.token,
          this.holder,
          (change: bigint) => change < 0n,
        ),
      ).to.be.rejectedWith(
        AssertionError,
        `Expected the confidential balance of ${symbol} tokens for "${this.holder.address}" to NOT satisfy the predicate, but it did (confidential balance change: -100)`,
      );
    });

    it('rejects a first argument that is not a contract', async function () {
      expect(() => expect(this.transfer(100)).to.changeConfidentialBalance(this.holder, this.holder, -100)).to.throw(
        'The first argument of changeConfidentialBalance must be the contract instance of the token',
      );
    });

    it('rejects a contract that is not an ERC7984 token', async function () {
      const erc20 = await ethers.deployContract('ERC20Mock', ['Public Token', 'PT', 6]);
      expect(() => expect(this.transfer(100)).to.changeConfidentialBalance(erc20, this.holder, -100)).to.throw(
        'The given contract instance is not an ERC7984 token',
      );
    });

    it('does not invoke a callback subject when the input is invalid', function () {
      let calls = 0;
      expect(() =>
        expect(() => (calls++, this.transfer(100))).to.changeConfidentialBalance(this.holder, this.holder, -100),
      ).to.throw('The first argument of changeConfidentialBalance must be the contract instance of the token');
      expect(calls).to.equal(0);
    });

    it('rejects a reverted transaction instead of reporting no balance change', async function () {
      const tx = this.token.connect(this.holder)['confidentialTransfer(address,uint64)'](ethers.ZeroAddress, 100);

      await expect(expect(tx).to.changeConfidentialBalance(this.token, this.holder, 0)).to.be.rejectedWith(
        'VM Exception while processing transaction: reverted',
      );
    });

    it('rejects a block containing multiple transactions', async function () {
      await network.provider.send('evm_setAutomine', [false]);
      try {
        const tx = await this.transfer(100);
        await this.other.sendTransaction({ to: this.other.address });
        await network.provider.send('evm_mine');

        await expect(expect(tx).to.changeConfidentialBalance(this.token, this.holder, -100)).to.be.rejectedWith(
          'Multiple transactions found in block',
        );
      } finally {
        await network.provider.send('evm_setAutomine', [true]);
      }
    });

    it('cannot be chained after another async matcher', async function () {
      const tx = this.transfer(100);
      expect(() =>
        expect(tx)
          .to.emit(this.token, 'ConfidentialTransfer')
          .and.to.changeConfidentialBalance(this.token, this.holder, -100),
      ).to.throw("The matcher 'changeConfidentialBalance' cannot be chained after 'emit'");
      await tx;
    });

    it('cannot be chained after a chai-as-promised assertion', async function () {
      const tx = this.transfer(100);
      // `fulfilled` is typed as a PromisedAssertion, which doesn't declare the hardhat matchers
      const assertion = expect(tx).to.be.fulfilled as unknown as Chai.Assertion;
      expect(() => assertion.and.to.changeConfidentialBalance(this.token, this.holder, -100)).to.throw(
        "The matcher 'changeConfidentialBalance' cannot be chained after another async matcher",
      );
      await tx;
    });

    it('cannot be chained after itself', async function () {
      const tx = this.transfer(100);
      expect(() =>
        expect(tx)
          .to.changeConfidentialBalance(this.token, this.holder, -100)
          .and.to.changeConfidentialBalance(this.token, this.recipient, 100),
      ).to.throw("The matcher 'changeConfidentialBalance' cannot be chained after 'changeConfidentialBalance'");
      await tx;
    });

    it('does not invoke a callback subject when chaining is rejected', function () {
      let calls = 0;
      expect(() =>
        expect(() => (calls++, this.transfer(100)))
          .to.changeConfidentialBalance(this.token, this.holder, -100)
          .and.to.changeConfidentialBalance(this.token, this.recipient, 100),
      ).to.throw("The matcher 'changeConfidentialBalance' cannot be chained after 'changeConfidentialBalance'");
      expect(calls).to.equal(1);
    });

    it('prevents other async matchers from being chained after it', async function () {
      const tx = this.transfer(100);
      expect(() =>
        expect(tx)
          .to.changeConfidentialBalance(this.token, this.holder, -100)
          .and.to.emit(this.token, 'ConfidentialTransfer'),
      ).to.throw("The matcher 'emit' cannot be chained after 'changeConfidentialBalance'");
      await tx;
    });
  });

  describe('changeConfidentialBalances', function () {
    it('asserts the balance changes of several accounts', async function () {
      await expect(this.transfer(100)).to.changeConfidentialBalances(
        this.token,
        [this.holder, this.recipient, this.other],
        [-100, 100, 0],
      );
    });

    it('accepts a predicate', async function () {
      await expect(this.transfer(100)).to.changeConfidentialBalances(
        this.token,
        [this.holder, this.recipient],
        ([holderChange, recipientChange]: bigint[]) => holderChange + recipientChange === 0n,
      );
    });

    it('supports negation', async function () {
      await expect(this.transfer(100)).to.not.changeConfidentialBalances(
        this.token,
        [this.holder, this.recipient],
        [-1, 1],
      );
    });

    it('fails when the balances change by different amounts', async function () {
      await expect(
        expect(this.transfer(100)).to.changeConfidentialBalances(this.token, [this.holder, this.recipient], [-1, 1]),
      ).to.be.rejectedWith(
        AssertionError,
        `Expected the confidential balances of ${symbol} tokens for ${this.holder.address}, ${this.recipient.address} to change by -1, 1, respectively, but they changed by -100, 100`,
      );
    });

    it('fails when the balances change by the amounts and the assertion is negated', async function () {
      await expect(
        expect(this.transfer(100)).to.not.changeConfidentialBalances(
          this.token,
          [this.holder, this.recipient],
          [-100, 100],
        ),
      ).to.be.rejectedWith(
        AssertionError,
        `Expected the confidential balances of ${symbol} tokens for ${this.holder.address}, ${this.recipient.address} NOT to change by -100, 100, respectively, but they did`,
      );
    });

    it('fails when the predicate is not satisfied', async function () {
      await expect(
        expect(this.transfer(100)).to.changeConfidentialBalances(
          this.token,
          [this.holder, this.recipient],
          (changes: bigint[]) => changes.every(change => change > 0n),
        ),
      ).to.be.rejectedWith(
        AssertionError,
        `Expected the confidential balance changes of ${symbol} to satisfy the predicate, but they didn't (confidential balance changes: -100, 100)`,
      );
    });

    it('rejects a mismatched number of accounts and balance changes', async function () {
      expect(() =>
        expect(this.transfer(100)).to.changeConfidentialBalances(this.token, [this.holder, this.recipient], [-100]),
      ).to.throw('The number of accounts (2) is different than the number of expected balance changes (1)');
    });

    it('does not invoke a callback subject when the input is invalid', function () {
      let calls = 0;
      expect(() =>
        expect(() => (calls++, this.transfer(100))).to.changeConfidentialBalances(
          this.token,
          [this.holder, this.recipient],
          [-100],
        ),
      ).to.throw('The number of accounts (2) is different than the number of expected balance changes (1)');
      expect(calls).to.equal(0);
    });

    it('rejects an account list that is not an array', function () {
      expect(() =>
        expect(this.transfer(100)).to.changeConfidentialBalances(this.token, this.holder.address, () => true),
      ).to.throw('The second argument of changeConfidentialBalances must be an array of accounts');
    });

    for (const balanceChanges of [[-100, 100], () => true]) {
      it(`rejects an undefined account list without invoking a callback subject (${
        typeof balanceChanges === 'function' ? 'predicate' : 'array'
      } of balance changes)`, function () {
        let calls = 0;
        expect(() =>
          expect(() => (calls++, this.transfer(100))).to.changeConfidentialBalances(
            this.token,
            undefined as any,
            balanceChanges as any,
          ),
        ).to.throw('The second argument of changeConfidentialBalances must be an array of accounts');
        expect(calls).to.equal(0);
      });
    }

    it('cannot be chained after another async matcher', async function () {
      const tx = this.transfer(100);
      expect(() =>
        expect(tx)
          .to.emit(this.token, 'ConfidentialTransfer')
          .and.to.changeConfidentialBalances(this.token, [this.holder, this.recipient], [-100, 100]),
      ).to.throw("The matcher 'changeConfidentialBalances' cannot be chained after 'emit'");
      await tx;
    });

    it('does not invoke a callback subject when chaining is rejected', function () {
      let calls = 0;
      expect(() =>
        expect(() => (calls++, this.transfer(100)))
          .to.changeConfidentialBalances(this.token, [this.holder, this.recipient], [-100, 100])
          .and.to.changeConfidentialBalances(this.token, [this.holder, this.recipient], [-100, 100]),
      ).to.throw("The matcher 'changeConfidentialBalances' cannot be chained after 'changeConfidentialBalances'");
      expect(calls).to.equal(1);
    });
  });
});
