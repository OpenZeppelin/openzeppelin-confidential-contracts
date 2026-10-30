import { getAcl } from '../helpers/acl';
import { delegatedUserDecryptEuint } from '../helpers/decrypt';
import { callAndGetResult } from '../helpers/event';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const WILDCARD = '0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF';
const NEVER_EXPIRES = 2n ** 64n - 1n;

const createHandle = (mock: any, amount: bigint) =>
  callAndGetResult(mock.createHandle(amount), 'HandleCreated(bytes32)').then(([handle]) => handle);

describe('Auditor', function () {
  beforeEach(async function () {
    const [holder, auditor, other] = await ethers.getSigners();
    const mock = await ethers.deployContract('$AuditorMock');

    const connectedAcl = (await getAcl()).connect(holder);
    // alias for easier readability
    const acl = Object.assign(connectedAcl, {
      isHandleDelegated: connectedAcl.isHandleDelegatedForUserDecryption,
      delegationExpiration: connectedAcl.getUserDecryptionDelegationExpirationDate,
    });

    Object.assign(this, { holder, auditor, other, mock, acl });
  });

  describe('add auditor', function () {
    it('grants a permanent wildcard decryption delegation', async function () {
      await this.mock.$_addAuditor(this.auditor);

      await expect(this.acl.delegationExpiration(this.mock, this.auditor, WILDCARD)).to.eventually.equal(NEVER_EXPIRES);
    });

    it('delegates decryption of handles the contract is allowed to decrypt', async function () {
      const amount = 42n;
      const handle = await createHandle(this.mock, amount);

      await expect(fhevm.userDecryptEuint(FhevmType.euint64, handle, this.mock, this.auditor)).to.be.rejectedWith(
        /not authorized to decrypt handle/,
      );

      await this.mock.$_addAuditor(this.auditor);

      await expect(this.acl.isHandleDelegated(this.mock, this.auditor, this.mock, handle)).to.eventually.be.true;
      await expect(this.acl.isHandleDelegated(this.mock, this.auditor, this.holder, handle)).to.eventually.be.true;
      await expect(this.acl.isHandleDelegated(this.mock, this.auditor, this.other, handle)).to.eventually.be.false;
      await expect(this.acl.isHandleDelegated(this.mock, this.other, this.mock, handle)).to.eventually.be.false;
      await expect(this.acl.isAllowed(handle, this.auditor)).to.eventually.be.false;

      await expect(delegatedUserDecryptEuint(handle, this.holder, this.mock, this.auditor)).to.eventually.equal(amount);
    });

    it('covers handles created after the auditor is added', async function () {
      await this.mock.$_addAuditor(this.auditor);

      const handle = await createHandle(this.mock, 7n);

      await expect(this.acl.isHandleDelegated(this.mock, this.auditor, this.mock, handle)).to.eventually.be.true;
    });

    it('does not cover handles the contract is not allowed to decrypt', async function () {
      const otherMock = await ethers.deployContract('$AuditorMock');
      const handle = await createHandle(otherMock.connect(this.holder), 7n);

      await this.mock.$_addAuditor(this.auditor);

      await expect(this.acl.isHandleDelegated(otherMock, this.auditor, otherMock, handle)).to.eventually.be.false;
    });

    it('reverts when the auditor is already active', async function () {
      // Add the auditor for the first time to set the wildcard delegation
      await this.mock.$_addAuditor(this.auditor);

      // Add the auditor for the second time should revert with the custom error
      await expect(this.mock.$_addAuditor(this.auditor))
        .to.be.revertedWithCustomError(this.acl, 'ExpirationDateAlreadySetToSameValue')
        .withArgs(this.mock, this.auditor, WILDCARD, NEVER_EXPIRES);
    });

    it('reverts when the auditor is the granting contract', async function () {
      await expect(this.mock.$_addAuditor(this.mock))
        .to.be.revertedWithCustomError(this.acl, 'SenderCannotBeDelegate')
        .withArgs(this.mock);
    });
  });

  describe('remove auditor', function () {
    it('revokes the wildcard delegation', async function () {
      const handle = await createHandle(this.mock, 42n);

      await this.mock.$_addAuditor(this.auditor);
      await expect(this.acl.delegationExpiration(this.mock, this.auditor, WILDCARD)).to.eventually.equal(NEVER_EXPIRES);
      await expect(this.acl.isHandleDelegated(this.mock, this.auditor, this.mock, handle)).to.eventually.be.true;

      await this.mock.$_removeAuditor(this.auditor);
      await expect(this.acl.delegationExpiration(this.mock, this.auditor, WILDCARD)).to.eventually.equal(0n);
      await expect(this.acl.isHandleDelegated(this.mock, this.auditor, this.mock, handle)).to.eventually.be.false;
    });

    it('reverts when the auditor was not added', async function () {
      await expect(this.mock.$_removeAuditor(this.auditor))
        .to.be.revertedWithCustomError(this.acl, 'NotDelegatedYet')
        .withArgs(this.mock, this.auditor, WILDCARD);
    });
  });
});
