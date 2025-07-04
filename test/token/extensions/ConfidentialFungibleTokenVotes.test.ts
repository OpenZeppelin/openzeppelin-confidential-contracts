// @ts-ignore
import { FhevmType } from '@fhevm/hardhat-plugin';
import { mine } from '@nomicfoundation/hardhat-network-helpers';
import { Delegation, getDomain } from '@openzeppelin/contracts/test/helpers/eip712';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleTokenVotes';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

describe('ConfidentialFungibleTokenVotes', function () {
  beforeEach(async function () {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const token = await ethers.deployContract('$ConfidentialFungibleTokenVotesMock', [name, symbol, uri]);

    this.accounts = accounts.slice(3);
    this.holder = holder;
    this.recipient = recipient;
    this.token = token;
    this.operator = operator;
    this.domain = await getDomain(this.token);

    const input = fhevm.createEncryptedInput(this.token.target, this.holder.address);
    input.add64(1000);
    this.encryptedInput = await input.encrypt();
  });

  describe('delegate', async function () {
    it('by default is null address', async function () {
      await expect(this.token.delegates(this.holder)).to.eventually.eq(ethers.ZeroAddress);
    });

    it('can be set', async function () {
      await expect(this.token.connect(this.holder).delegate(this.recipient))
        .to.emit(this.token, 'DelegateChanged')
        .withArgs(this.holder, ethers.ZeroAddress, this.recipient);

      await expect(this.token.delegates(this.holder)).to.eventually.eq(this.recipient);
    });

    describe('by sig', function () {
      for (let nonce of [0, 1]) {
        it(`with ${nonce == 0 ? 'valid' : 'invalid'} nonce`, async function () {
          const { r, s, v } = await this.holder
            .signTypedData(
              this.domain,
              { Delegation },
              { delegatee: this.recipient.address, nonce, expiry: ethers.MaxUint256 },
            )
            .then(ethers.Signature.from);

          const tx = this.token
            .connect(this.operator)
            .delegateBySig(this.recipient.address, nonce, ethers.MaxUint256, v, r, s);

          if (nonce == 1) {
            await expect(tx)
              .to.be.revertedWithCustomError(this.token, 'InvalidAccountNonce')
              .withArgs(this.holder.address, 0);
          } else {
            await tx;
            await expect(this.token.delegates(this.holder)).to.eventually.eq(this.recipient);
          }
        });
      }

      for (let expiry of [ethers.MaxUint256, 0]) {
        it(`with ${expiry == ethers.MaxUint256 ? 'valid' : 'invalid'} expiry`, async function () {
          const { r, s, v } = await this.holder
            .signTypedData(this.domain, { Delegation }, { delegatee: this.recipient.address, nonce: 0, expiry })
            .then(ethers.Signature.from);

          const tx = this.token.connect(this.operator).delegateBySig(this.recipient.address, 0, expiry, v, r, s);

          if (expiry == 0n) {
            await expect(tx).to.be.revertedWithCustomError(this.token, 'VotesExpiredSignature').withArgs(expiry);
          } else {
            await tx;
            await expect(this.token.delegates(this.holder)).to.eventually.eq(this.recipient);
          }
        });
      }

      it('with invalid signature', async function () {
        const expiry = ethers.MaxUint256;
        const { r, s } = await this.holder
          .signTypedData(this.domain, { Delegation }, { delegatee: this.recipient.address, nonce: 0, expiry })
          .then(ethers.Signature.from);

        await expect(
          this.token.connect(this.operator).delegateBySig(this.recipient.address, 0, expiry, 0, r, s),
        ).to.be.revertedWithCustomError(this.token, 'ECDSAInvalidSignature');
      });
    });
  });

  describe('getVotes', async function () {
    it('for account with zero balance', async function () {
      await expect(this.token.getVotes(this.holder)).to.eventually.eq(ethers.ZeroHash);
    });

    it('for account with non-zero balance', async function () {
      await this.token['$_mint(address,bytes32,bytes)'](
        this.holder,
        this.encryptedInput.handles[0],
        this.encryptedInput.inputProof,
      );
      await this.token.connect(this.holder).delegate(this.holder);

      const votesHandle = await this.token.getVotes(this.holder);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, votesHandle, this.token.target, this.holder),
      ).to.eventually.equal(1000);
    });

    it('for account with non-zero balance cannot reencrypt by other', async function () {
      await this.token['$_mint(address,bytes32,bytes)'](
        this.holder,
        this.encryptedInput.handles[0],
        this.encryptedInput.inputProof,
      );
      await this.token.connect(this.holder).delegate(this.holder);

      const votesHandle = await this.token.getVotes(this.holder);
      await expect(fhevm.userDecryptEuint(FhevmType.euint64, votesHandle, this.token.target, this.operator)).to
        .eventually.rejected;
    });
  });

  describe('getPastVotes', async function () {
    beforeEach(async function () {
      this.blockNumber = await ethers.provider.getBlockNumber();
    });

    it('for account with no activity', async function () {
      await expect(this.token.getPastVotes(this.holder, this.blockNumber - 10)).to.eventually.eq(ethers.ZeroHash);
    });

    it('for account with simple activity', async function () {
      await this.token.connect(this.holder).delegate(this.holder);
      await this.token['$_mint(address,bytes32,bytes)'](
        this.holder,
        this.encryptedInput.handles[0],
        this.encryptedInput.inputProof,
      );
      const afterVotesBlock = await ethers.provider.getBlockNumber();
      await mine();

      await expect(this.token.getPastVotes(this.holder, this.blockNumber)).to.eventually.eq(ethers.ZeroHash);

      const votesHandle = await this.token.getPastVotes(this.holder, afterVotesBlock);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, votesHandle, this.token.target, this.holder),
      ).to.eventually.equal(1000);
    });

    it('for account with complex activity', async function () {
      // Initial mint of 1000
      await this.token.connect(this.holder).delegate(this.holder);
      await this.token['$_mint(address,bytes32,bytes)'](
        this.holder,
        this.encryptedInput.handles[0],
        this.encryptedInput.inputProof,
      );
      const afterInitialMintBlock = await ethers.provider.getBlockNumber();

      // Transfer 200 to other address
      const input = fhevm.createEncryptedInput(this.token.target, this.holder.address);
      input.add64(200);
      const encryptedInput = await input.encrypt();
      await this.token
        .connect(this.holder)
        ['confidentialTransfer(address,bytes32,bytes)'](
          this.operator,
          encryptedInput.handles[0],
          encryptedInput.inputProof,
        );
      const afterTransferBlock = await ethers.provider.getBlockNumber();

      // Burn total balance
      const amountToBurn = await this.token.balanceOf(this.holder);
      await this.token.$_burn(this.holder, amountToBurn);
      const afterBurnBlock = await ethers.provider.getBlockNumber();
      await mine();

      await expect(this.token.getPastVotes(this.holder, this.blockNumber)).to.eventually.eq(ethers.ZeroHash);

      const afterInitialMintVotesHandle = await this.token.getPastVotes(this.holder, afterInitialMintBlock);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterInitialMintVotesHandle, this.token.target, this.holder),
      ).to.eventually.equal(1000);

      const afterTransferVotesHandle = await this.token.getPastVotes(this.holder, afterTransferBlock);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterTransferVotesHandle, this.token.target, this.holder),
      ).to.eventually.equal(800);

      const afterBurnVotesHandle = await this.token.getPastVotes(this.holder, afterBurnBlock);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterBurnVotesHandle, this.token.target, this.holder),
      ).to.eventually.equal(0);
    });

    it('in the future', async function () {
      await expect(this.token.getPastVotes(this.holder, this.blockNumber + 10))
        .to.be.revertedWithCustomError(this.token, 'ERC5805FutureLookup')
        .withArgs(this.blockNumber + 10, this.blockNumber);
    });
  });

  describe('getPastTotalSupply', function () {
    beforeEach(async function () {
      this.blockNumber = await ethers.provider.getBlockNumber();
    });

    it('for no activity', async function () {
      await mine();
      await expect(this.token.getPastTotalSupply(this.blockNumber)).to.eventually.eq(ethers.ZeroHash);
    });

    it('for multiple mints and transfers', async function () {
      // Mint to holder
      await this.token['$_mint(address,bytes32,bytes)'](
        this.holder,
        this.encryptedInput.handles[0],
        this.encryptedInput.inputProof,
      );
      const afterFirstMintBlock = await ethers.provider.getBlockNumber();

      // Transfer to operator
      const input = fhevm.createEncryptedInput(this.token.target, this.holder.address);
      input.add64(200);
      const encryptedInput = await input.encrypt();
      await this.token
        .connect(this.holder)
        ['confidentialTransfer(address,bytes32,bytes)'](
          this.operator,
          encryptedInput.handles[0],
          encryptedInput.inputProof,
        );
      const afterTransferBlock = await ethers.provider.getBlockNumber();

      // Mint to recipient
      await this.token['$_mint(address,bytes32,bytes)'](
        this.recipient,
        this.encryptedInput.handles[0],
        this.encryptedInput.inputProof,
      );
      const afterSecondMintBlock = await ethers.provider.getBlockNumber();

      // Mine block to avoid future lookup
      await mine();

      // Check total supply for each block
      const afterFirstMintSupplyHandle = await this.token.getPastTotalSupply(afterFirstMintBlock);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterFirstMintSupplyHandle, this.token.target, this.holder),
      ).to.eventually.equal(1000);

      await expect(this.token.getPastTotalSupply(afterTransferBlock)).to.eventually.eq(afterFirstMintSupplyHandle);

      const afterSecondMintSupplyHandle = await this.token.getPastTotalSupply(afterSecondMintBlock);
      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, afterSecondMintSupplyHandle, this.token.target, this.holder),
      ).to.eventually.equal(2000);
    });
  });

  describe('Clock', async function () {
    it('check CLOCK_MODE', async function () {
      await expect(this.token.CLOCK_MODE()).to.eventually.eq('mode=blocknumber&from=default');
    });

    it('clock inconsistency', async function () {
      await this.token._setClockOverride(1000);

      await expect(this.token.CLOCK_MODE()).to.be.revertedWithCustomError(this.token, 'ERC6372InconsistentClock');
    });
  });
});
