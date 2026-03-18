import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';
const transferAmount = 42n;

describe('ERC7984IdentityCheck', function () {
  beforeEach(async function () {
    const [holder, recipient, operator, anyone] = await ethers.getSigners();

    const identityRegistry = await ethers.deployContract('IdentityRegistryMock');
    const token = await ethers.deployContract('$ERC7984IdentityCheckMock', [
      identityRegistry.target,
      name,
      symbol,
      uri,
    ]);

    await identityRegistry.setVerified(holder.address, true);
    await token['$_mint(address,uint64)'](holder, 1000);

    Object.assign(this, { identityRegistry, token, holder, recipient, operator, anyone });
  });

  it('returns the identity registry address', async function () {
    await expect(this.token.identityRegistry()).to.eventually.equal(this.identityRegistry.target);
  });

  describe('mint', function () {
    it('allows minting to a verified user', async function () {
      await this.identityRegistry.setVerified(this.recipient.address, true);

      await this.token['$_mint(address,uint64)'](this.recipient, transferAmount);
    });

    it('reverts when minting to an unverified user', async function () {
      await expect(this.token['$_mint(address,uint64)'](this.recipient, transferAmount))
        .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidIdentity')
        .withArgs(this.recipient);
    });
  });

  describe('transfer', function () {
    it('allows transfer to a verified user', async function () {
      await this.identityRegistry.setVerified(this.recipient.address, true);

      const encryptedAmount = await fhevm
        .createEncryptedInput(this.token.target, this.holder.address)
        .add64(transferAmount)
        .encrypt();

      await this.token
        .connect(this.holder)
        ['confidentialTransfer(address,bytes32,bytes)'](
          this.recipient.address,
          encryptedAmount.handles[0],
          encryptedAmount.inputProof,
        );
    });

    it('reverts when transferring to an unverified user', async function () {
      const encryptedInput = await fhevm
        .createEncryptedInput(this.token.target, this.holder.address)
        .add64(transferAmount)
        .encrypt();

      await expect(
        this.token
          .connect(this.holder)
          ['confidentialTransfer(address,bytes32,bytes)'](
            this.recipient.address,
            encryptedInput.handles[0],
            encryptedInput.inputProof,
          ),
      )
        .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidIdentity')
        .withArgs(this.recipient);
    });

    it('allows transfer from an unverified sender to a verified recipient', async function () {
      await this.identityRegistry.setVerified(this.recipient.address, true);
      await this.identityRegistry.setVerified(this.holder.address, false);

      const encryptedInput = await fhevm
        .createEncryptedInput(this.token.target, this.holder.address)
        .add64(transferAmount)
        .encrypt();

      await this.token
        .connect(this.holder)
        ['confidentialTransfer(address,bytes32,bytes)'](
          this.recipient.address,
          encryptedInput.handles[0],
          encryptedInput.inputProof,
        );
    });
  });

  it('burn succeeds', async function () {
    await this.token.connect(this.holder)['$_burn(address,uint64)'](this.holder, transferAmount);
  });
});
