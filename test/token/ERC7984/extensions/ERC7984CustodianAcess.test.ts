import { FhevmType } from '@fhevm/hardhat-plugin';
import { mine } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'Custodian Access Token';
const symbol = 'CAT';
const uri = 'https://example.com/metadata';

describe('ERC7984CustodianAccess', function () {
  beforeEach(async function () {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const token = await ethers.deployContract('$ERC7984CustodianAccessMock', [name, symbol, uri]);
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

  it('should be able to set a custodian from holder', async function () {
    const custodian = this.operator;

    await expect(this.token.connect(this.holder).setCustodian(this.holder, custodian))
      .to.emit(this.token, 'ERC7984CustodianAccessCustodianSet')
      .withArgs(this.holder.address, ethers.ZeroAddress, custodian.address);
    await expect(this.token.custodian(this.holder)).to.eventually.equal(custodian.address);
  });

  it('setting custodian to existing custodian should be a noop', async function () {
    const custodian = this.operator;
    await this.token.connect(this.holder).setCustodian(this.holder, custodian);

    await expect(this.token.connect(this.holder).setCustodian(this.holder, custodian)).to.not.emit(
      this.token,
      'ERC7984CustodianAccessCustodianSet',
    );
  });

  it('should not be able to set a custodian from non-holder', async function () {
    const custodian = this.operator;
    await expect(this.token.connect(this.recipient).setCustodian(this.holder, custodian))
      .to.be.revertedWithCustomError(this.token, 'Unauthorized')
      .withArgs();
  });

  it('custodian should be able to set a custodian to zero address', async function () {
    const custodian = this.operator;

    await expect(this.token.connect(this.holder).setCustodian(this.holder, custodian));
    await expect(this.token.connect(custodian).setCustodian(this.holder, ethers.ZeroAddress))
      .to.emit(this.token, 'ERC7984CustodianAccessCustodianSet')
      .withArgs(this.holder.address, custodian.address, ethers.ZeroAddress);
    await expect(this.token.custodian(this.holder)).to.eventually.equal(ethers.ZeroAddress);
  });

  for (const sender of [true, false]) {
    it(`${sender ? 'sender' : 'recipient'} custodian should be able to reencrypt transfer amounts`, async function () {
      const custodian = this.operator;

      const custodianFor = sender ? this.holder : this.recipient;
      await expect(this.token.connect(custodianFor).setCustodian(custodianFor, custodian))
        .to.emit(this.token, 'ERC7984CustodianAccessCustodianSet')
        .withArgs(custodianFor.address, ethers.ZeroAddress, custodian.address);

      const encryptedInput = await fhevm
        .createEncryptedInput(this.token.target, this.holder.address)
        .add64(100)
        .encrypt();

      const tx = await this.token
        .connect(this.holder)
        ['confidentialTransfer(address,bytes32,bytes)'](
          this.recipient,
          encryptedInput.handles[0],
          encryptedInput.inputProof,
        );

      const transferredHandle = await tx
        .wait()
        .then((receipt: any) => receipt.logs.filter((log: any) => log.address === this.token.target)[0].args[2]);

      await mine(1);

      await expect(
        fhevm.userDecryptEuint(FhevmType.euint64, transferredHandle, this.token.target, custodian),
      ).to.eventually.equal(100);
    });
  }
});
