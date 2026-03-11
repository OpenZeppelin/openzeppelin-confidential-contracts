import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

describe('HandleAccessManager', function () {
  before(async function () {
    const accounts = await ethers.getSigners();
    const mock = await ethers.deployContract('HandleAccessManagerMock');

    this.mock = mock;
    this.holder = accounts[0];
  });

  it('should not be allowed to reencrypt unallowed handle', async function () {
    const handle = await createHandle(this.mock, 101);

    await expect(fhevm.userDecryptEuint(FhevmType.euint64, handle, this.mock.target, this.holder)).to.be.rejectedWith(
      `User ${this.holder.address} is not authorized to user decrypt handle ${handle}`,
    );
  });

  it('should be allowed to reencrypt allowed handle', async function () {
    const handle = await createHandle(this.mock, 200);
    await this.mock.getHandleAllowance(handle, this.holder.address, true);

    await expect(fhevm.userDecryptEuint(FhevmType.euint64, handle, this.mock.target, this.holder)).to.eventually.eq(
      200,
    );
  });

  it('transient allowance should work', async function () {
    const transientAllowanceUser = await ethers.deployContract('HandleAccessManagerUserMock');

    const handle = await createHandle(this.mock, 300);
    await transientAllowanceUser.getTransientAllowance(this.mock, handle);
  });

  it('transient allowance should reset', async function () {
    const handle = await createHandle(this.mock, 400);
    await this.mock.getHandleAllowance(handle, this.holder.address, false);

    await expect(fhevm.userDecryptEuint(FhevmType.euint64, handle, this.mock.target, this.holder)).to.be.rejectedWith(
      `User ${this.holder.address} is not authorized to user decrypt handle ${handle}`,
    );
  });
});

const createHandle = async (mock: any, amount: number): Promise<string> => {
  const tx = await mock.createHandle(amount);
  const receipt = await tx.wait();
  return receipt.logs.filter((log: any) => log.address === mock.target)[0].args[0];
};
