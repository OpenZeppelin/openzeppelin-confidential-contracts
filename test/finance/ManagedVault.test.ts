import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers } from 'hardhat';

async function fixture() {
  const accounts = await ethers.getSigners();
  const [owner, other] = accounts;

  const managedVault = await ethers.deployContract('ManagedVault', owner);
  await expect(managedVault.owner()).to.eventually.eq(owner);

  return { owner, other, managedVault };
}

describe('ManagedVault', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('owner can execute calls', async function () {
    await this.managedVault.connect(this.owner).call(this.owner, 0, '0x');
  });

  it('reverted call is bubbled up', async function () {
    const populatedTx = await this.managedVault.call.populateTransaction(this.owner, 0, '0x');

    await expect(this.managedVault.connect(this.owner).call(populatedTx.to, 0, populatedTx.data))
      .to.be.revertedWithCustomError(this.managedVault, 'MangedVaultUnauthorizedAccount')
      .withArgs(this.managedVault);
  });

  it('non-owner can not execute call', async function () {
    await expect(this.managedVault.connect(this.other).call(this.owner, 0, '0x'))
      .to.be.revertedWithCustomError(this.managedVault, 'MangedVaultUnauthorizedAccount')
      .withArgs(this.other);
  });
});
