import { IACL__factory } from '../../../../types';
import { $ERC7984OmnibusMock } from '../../../../types/contracts-exposed/mocks/token/ERC7984OmnibusMock.sol/$ERC7984OmnibusMock';
import { ACL_ADDRESS } from '../../../helpers/accounts';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'OmnibusToken';
const symbol = 'OBT';
const uri = 'https://example.com/metadata';

describe('ERC7984Omnibus', function () {
  beforeEach(async function () {
    const [holder, recipient, operator, subaccount] = await ethers.getSigners();
    const token = (await ethers.deployContract('$ERC7984OmnibusMock', [
      name,
      symbol,
      uri,
    ])) as any as $ERC7984OmnibusMock;
    const acl = IACL__factory.connect(ACL_ADDRESS, ethers.provider);
    Object.assign(this, { token, acl, holder, recipient, operator, subaccount });

    await this.token['$_mint(address,uint64)'](this.holder.address, 1000);
  });

  for (const transferFrom of [true, false]) {
    describe(`omnibus ${transferFrom ? 'transferFrom' : 'transfer'}`, function () {
      beforeEach(async function () {
        if (transferFrom) {
          await this.token.connect(this.holder).setOperator(this.operator.address, 999999999999);
        }
      });

      it('normal transfer', async function () {
        const caller = transferFrom ? this.operator : this.holder;

        const encryptedInput = await fhevm
          .createEncryptedInput(this.token.target, caller.address)
          .addAddress(this.subaccount.address)
          .add64(100)
          .encrypt();
        const args = [
          this.recipient.address,
          encryptedInput.handles[0],
          encryptedInput.handles[1],
          encryptedInput.inputProof,
        ];
        if (transferFrom) {
          args.unshift(this.holder.address);
        }
        const tx = await this.token
          .connect(caller)
          [
            transferFrom
              ? 'confidentialTransferFromOmnibus(address,address,bytes32,bytes32,bytes)'
              : 'confidentialTransferOmnibus(address,bytes32,bytes32,bytes)'
          ](...args);
        const omnibusTransferEvent = (await tx.wait()).logs.filter(
          (log: any) => log.fragment?.name === 'OmnibusTransfer',
        )[0];
        expect(omnibusTransferEvent.args[0]).to.equal(this.holder.address);
        expect(omnibusTransferEvent.args[1]).to.equal(this.recipient.address);

        await expect(
          fhevm.userDecryptEaddress(omnibusTransferEvent.args[2], this.token.target, this.holder),
        ).to.eventually.equal(this.subaccount.address);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, omnibusTransferEvent.args[3], this.token.target, this.holder),
        ).to.eventually.equal(100);

        await expect(this.acl.isAllowed(omnibusTransferEvent.args[2], this.holder)).to.eventually.be.true;
        await expect(this.acl.isAllowed(omnibusTransferEvent.args[2], this.recipient)).to.eventually.be.true;
        await expect(this.acl.isAllowed(omnibusTransferEvent.args[2], this.operator)).to.eventually.be.false;
      });

      it('transfer more than balance', async function () {
        const caller = transferFrom ? this.operator : this.holder;

        const encryptedInput = await fhevm
          .createEncryptedInput(this.token.target, caller.address)
          .addAddress(this.subaccount.address)
          .add64(10000)
          .encrypt();
        const args = [
          this.recipient.address,
          encryptedInput.handles[0],
          encryptedInput.handles[1],
          encryptedInput.inputProof,
        ];
        if (transferFrom) {
          args.unshift(this.holder.address);
        }
        const tx = await this.token
          .connect(caller)
          [
            transferFrom
              ? 'confidentialTransferFromOmnibus(address,address,bytes32,bytes32,bytes)'
              : 'confidentialTransferOmnibus(address,bytes32,bytes32,bytes)'
          ](...args);
        const omnibusTransferEvent = (await tx.wait()).logs.filter(
          (log: any) => log.fragment?.name === 'OmnibusTransfer',
        )[0];
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, omnibusTransferEvent.args[3], this.token.target, this.holder),
        ).to.eventually.equal(0);

        await expect(this.acl.isAllowed(omnibusTransferEvent.args[2], this.holder)).to.eventually.be.true;
        await expect(this.acl.isAllowed(omnibusTransferEvent.args[2], this.recipient)).to.eventually.be.true;
        await expect(this.acl.isAllowed(omnibusTransferEvent.args[2], this.operator)).to.eventually.be.false;
      });
    });
  }
});
