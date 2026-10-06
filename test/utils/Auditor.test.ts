import { getAcl } from '../helpers/acl';
import { delegatedUserDecryptEuint } from '../helpers/decrypt';
import { callAndGetResult } from '../helpers/event';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { mine } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const WILDCARD = '0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF';
const NEVER_EXPIRES = 2n ** 64n - 1n;
const handleCreatedSignature = 'HandleCreated(bytes32)';

describe('Auditor', function () {
  beforeEach(async function () {
    const [holder, auditor, other] = await ethers.getSigners();
    const mock = await ethers.deployContract('$AuditorMock');
    const acl = (await getAcl()).connect(holder);

    Object.assign(this, { holder, auditor, other, mock, acl });
  });

  describe('add auditor', function () {
    it('grants a permanent wildcard decryption delegation', async function () {
      await this.mock.$_addAuditor(this.auditor.address);

      await expect(wildcardDelegationExpiration(this)).to.eventually.equal(NEVER_EXPIRES);
    });

    it('delegates decryption of handles the contract is allowed to decrypt', async function () {
      const amount = 42n;
      const handle = await createHandle(this.mock.connect(this.holder), amount);

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, handle, this.mock.target, this.auditor),
      ).to.be.rejectedWith(/not authorized to decrypt handle/);

      await this.mock.$_addAuditor(this.auditor.address);

      await expect(isHandleDelegated(this, this.mock, handle)).to.eventually.be.true;
      await expect(isHandleDelegated(this, this.holder, handle)).to.eventually.be.true;
      await expect(this.acl.isAllowed(handle, this.auditor.address)).to.eventually.be.false;
      await expect(
        this.acl.isHandleDelegatedForUserDecryption(this.mock.target, this.other.address, this.mock.target, handle),
      ).to.eventually.be.false;

      await expect(delegatedUserDecryptEuint(handle, this.holder, this.mock, this.auditor)).to.eventually.equal(amount);
    });

    it('covers handles created after the auditor is added', async function () {
      await this.mock.$_addAuditor(this.auditor.address);

      const handle = await createHandle(this.mock.connect(this.holder), 7n);

      await expect(isHandleDelegated(this, this.mock, handle)).to.eventually.be.true;
    });

    it('does not cover handles the contract is not allowed to decrypt', async function () {
      const otherMock = await ethers.deployContract('$AuditorMock');
      const handle = await createHandle(otherMock.connect(this.holder), 7n);

      await this.mock.$_addAuditor(this.auditor.address);

      await expect(isHandleDelegated(this, otherMock, handle)).to.eventually.be.false;
    });

    it('reverts when the auditor is already active', async function () {
      await this.mock.$_addAuditor(this.auditor.address);
      await mine();

      await expect(this.mock.$_addAuditor(this.auditor.address))
        .to.be.revertedWithCustomError(this.acl, 'ExpirationDateAlreadySetToSameValue')
        .withArgs(this.mock.target, this.auditor.address, WILDCARD, NEVER_EXPIRES);
    });

    it('reverts when the auditor is the granting contract', async function () {
      await expect(this.mock.$_addAuditor(this.mock.target))
        .to.be.revertedWithCustomError(this.acl, 'SenderCannotBeDelegate')
        .withArgs(this.mock.target);
    });
  });

  describe('remove auditor', function () {
    it('revokes the wildcard delegation', async function () {
      const handle = await createHandle(this.mock.connect(this.holder), 42n);

      await this.mock.$_addAuditor(this.auditor.address);
      await mine();
      await this.mock.$_removeAuditor(this.auditor.address);

      await expect(wildcardDelegationExpiration(this)).to.eventually.equal(0n);
      await expect(isHandleDelegated(this, this.mock, handle)).to.eventually.be.false;
    });

    it('reverts when the auditor was not added', async function () {
      await expect(this.mock.$_removeAuditor(this.auditor.address))
        .to.be.revertedWithCustomError(this.acl, 'NotDelegatedYet')
        .withArgs(this.mock.target, this.auditor.address, WILDCARD);
    });
  });
});

const createHandle = async (mock: any, amount: bigint) => {
  const [handle] = await callAndGetResult(mock.createHandle(amount), handleCreatedSignature);
  return handle;
};

const wildcardDelegationExpiration = (ctx: any) =>
  ctx.acl.getUserDecryptionDelegationExpirationDate(ctx.mock.target, ctx.auditor.address, WILDCARD);

const isHandleDelegated = (ctx: any, contractAddress: any, handle: string) =>
  ctx.acl.isHandleDelegatedForUserDecryption(ctx.mock.target, ctx.auditor.address, contractAddress, handle);
