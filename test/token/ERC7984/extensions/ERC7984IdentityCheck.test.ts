import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const transferAmount = 42n;

describe('ERC7984IdentityCheck', function () {
  beforeEach(async function () {
    const [holder, recipient, operator, anyone] = await ethers.getSigners();

    const identityRegistry = await ethers.deployContract('IdentityRegistryMock');
    const token = await ethers.deployContract('$ERC7984IdentityCheckMock', [identityRegistry.target, name, symbol]);

    await identityRegistry.setVerified(holder.address, true);
    await token['$_mint(address,uint64)'](holder, 1000);

    Object.assign(this, { identityRegistry, token, holder, recipient, operator, anyone });
  });

  describe('constructor', function () {
    it('sets the identity registry', async function () {
      await expect(this.token.identityRegistry()).to.eventually.equal(this.identityRegistry.target);
    });

    it('emits IdentityRegistryUpdated with zero previous registry', async function () {
      const token = await ethers.deployContract('$ERC7984IdentityCheckMock', [this.identityRegistry, name, symbol]);
      await expect(token.deploymentTransaction())
        .to.emit(token, 'IdentityRegistryUpdated')
        .withArgs(ethers.ZeroAddress, this.identityRegistry);
    });
  });

  it('returns the identity registry address', async function () {
    await expect(this.token.identityRegistry()).to.eventually.equal(this.identityRegistry.target);
  });

  describe('_setIdentityRegistry', function () {
    it('updates the registry and emits an event', async function () {
      const newRegistry = await ethers.deployContract('IdentityRegistryMock');

      await expect(this.token.$_setIdentityRegistry(newRegistry.target))
        .to.emit(this.token, 'IdentityRegistryUpdated')
        .withArgs(this.identityRegistry.target, newRegistry.target);

      await expect(this.token.identityRegistry()).to.eventually.equal(newRegistry.target);
    });

    it('reverts if the new registry address is zero', async function () {
      await expect(this.token.$_setIdentityRegistry(ethers.ZeroAddress))
        .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidIdentityRegistry')
        .withArgs(ethers.ZeroAddress);
    });

    it('reverts if the new registry address is not a contract', async function () {
      await expect(this.token.$_setIdentityRegistry(this.anyone.address))
        .to.be.revertedWithCustomError(this.token, 'ERC7984InvalidIdentityRegistry')
        .withArgs(this.anyone.address);
    });
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
