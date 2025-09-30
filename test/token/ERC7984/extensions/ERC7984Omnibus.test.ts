import { IACL__factory } from '../../../../types';
import { $ERC7984OmnibusMock } from '../../../../types/contracts-exposed/mocks/token/ERC7984OmnibusMock.sol/$ERC7984OmnibusMock';
import { getAclAddress } from '../../../helpers/accounts';
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
    const acl = IACL__factory.connect(await getAclAddress(), ethers.provider);
    Object.assign(this, { token, acl, holder, recipient, operator, subaccount });

    await this.token['$_mint(address,uint64)'](this.holder.address, 1000);
  });

  for (const transferFrom of [true, false]) {
    describe(`omnibus ${transferFrom ? 'transferFrom' : 'transfer'}`, function () {
      for (const withCallback of [true, false]) {
        describe(withCallback ? 'with callback' : 'without callback', function () {
          for (const withProof of [true, false]) {
            describe(withProof ? 'with transfer proof' : 'without transfer proof', function () {
              beforeEach(async function () {
                if (transferFrom) {
                  await this.token.connect(this.holder).setOperator(this.operator.address, 999999999999);
                }
              });

              it('normal transfer', async function () {
                const caller = transferFrom ? this.operator : this.holder;

                let encryptedInputWithProof;
                let encryptedInput: { handles: any[] } = { handles: [] };
                if (withProof) {
                  encryptedInputWithProof = await fhevm
                    .createEncryptedInput(this.token.target, caller.address)
                    .addAddress(this.holder.address)
                    .addAddress(this.subaccount.address)
                    .add64(100)
                    .encrypt();
                } else {
                  let tx = await this.token.connect(caller).createEncryptedAddress(this.holder.address);
                  encryptedInput.handles.push(
                    (await tx.wait()).logs.filter((log: any) => log.fragment?.name === 'EncryptedAddressCreated')[0]
                      .args[0],
                  );

                  tx = await this.token.connect(caller).createEncryptedAddress(this.subaccount);
                  encryptedInput.handles.push(
                    (await tx.wait()).logs.filter((log: any) => log.fragment?.name === 'EncryptedAddressCreated')[0]
                      .args[0],
                  );

                  tx = await this.token.connect(caller).createEncryptedAmount(100);
                  encryptedInput.handles.push(
                    (await tx.wait()).logs.filter((log: any) => log.fragment?.name === 'EncryptedAmountCreated')[0]
                      .args[0],
                  );
                }

                const args = [
                  this.recipient.address,
                  (withProof ? encryptedInputWithProof : encryptedInput)?.handles[0],
                  (withProof ? encryptedInputWithProof : encryptedInput)?.handles[1],
                  (withProof ? encryptedInputWithProof : encryptedInput)?.handles[2],
                ];
                if (transferFrom) {
                  args.unshift(this.holder.address);
                }
                if (withProof) {
                  args.push(encryptedInputWithProof?.inputProof);
                }
                if (withCallback) {
                  args.push('0x');
                }

                const tx = await doConfidentialTransferOmnibus(
                  this.token.connect(caller),
                  transferFrom,
                  withCallback,
                  withProof,
                  args,
                );

                const omnibusConfidentialTransferEvent = (await tx.wait()).logs.filter(
                  (log: any) => log.fragment?.name === 'OmnibusConfidentialTransfer',
                )[0];
                expect(omnibusConfidentialTransferEvent.args[0]).to.equal(this.holder.address);
                expect(omnibusConfidentialTransferEvent.args[1]).to.equal(this.recipient.address);

                await expect(
                  fhevm.userDecryptEaddress(omnibusConfidentialTransferEvent.args[2], this.token.target, this.holder),
                ).to.eventually.equal(this.holder.address);
                await expect(
                  fhevm.userDecryptEaddress(omnibusConfidentialTransferEvent.args[3], this.token.target, this.holder),
                ).to.eventually.equal(this.subaccount.address);

                await expect(
                  fhevm.userDecryptEuint(
                    FhevmType.euint64,
                    omnibusConfidentialTransferEvent.args[4],
                    this.token.target,
                    this.holder,
                  ),
                ).to.eventually.equal(100);

                await expect(
                  this.acl.isAllowed(omnibusConfidentialTransferEvent.args[2], this.holder),
                ).to.eventually.be.true;
                await expect(
                  this.acl.isAllowed(omnibusConfidentialTransferEvent.args[2], this.recipient),
                ).to.eventually.be.true;
              });

              it('transfer more than balance', async function () {
                const caller = transferFrom ? this.operator : this.holder;

                let encryptedInputWithProof;
                let encryptedInput: { handles: any[] } = { handles: [] };
                if (withProof) {
                  encryptedInputWithProof = await fhevm
                    .createEncryptedInput(this.token.target, caller.address)
                    .addAddress(this.holder.address)
                    .addAddress(this.subaccount.address)
                    .add64(10000)
                    .encrypt();
                } else {
                  let tx = await this.token.connect(caller).createEncryptedAddress(this.holder.address);
                  encryptedInput.handles.push(
                    (await tx.wait()).logs.filter((log: any) => log.fragment?.name === 'EncryptedAddressCreated')[0]
                      .args[0],
                  );

                  tx = await this.token.connect(caller).createEncryptedAddress(this.subaccount);
                  encryptedInput.handles.push(
                    (await tx.wait()).logs.filter((log: any) => log.fragment?.name === 'EncryptedAddressCreated')[0]
                      .args[0],
                  );

                  tx = await this.token.connect(caller).createEncryptedAmount(10000);
                  encryptedInput.handles.push(
                    (await tx.wait()).logs.filter((log: any) => log.fragment?.name === 'EncryptedAmountCreated')[0]
                      .args[0],
                  );
                }

                const args = [
                  this.recipient.address,
                  (withProof ? encryptedInputWithProof : encryptedInput)?.handles[0],
                  (withProof ? encryptedInputWithProof : encryptedInput)?.handles[1],
                  (withProof ? encryptedInputWithProof : encryptedInput)?.handles[2],
                ];
                if (transferFrom) {
                  args.unshift(this.holder.address);
                }
                if (withProof) {
                  args.push(encryptedInputWithProof?.inputProof);
                }
                if (withCallback) {
                  args.push('0x');
                }

                const tx = await doConfidentialTransferOmnibus(
                  this.token.connect(caller),
                  transferFrom,
                  withCallback,
                  withProof,
                  args,
                );
                const omnibusConfidentialTransferEvent = (await tx.wait()).logs.filter(
                  (log: any) => log.fragment?.name === 'OmnibusConfidentialTransfer',
                )[0];
                await expect(
                  fhevm.userDecryptEuint(
                    FhevmType.euint64,
                    omnibusConfidentialTransferEvent.args[4],
                    this.token.target,
                    this.holder,
                  ),
                ).to.eventually.equal(0);

                await expect(
                  this.acl.isAllowed(omnibusConfidentialTransferEvent.args[2], this.holder),
                ).to.eventually.be.true;
                await expect(
                  this.acl.isAllowed(omnibusConfidentialTransferEvent.args[2], this.recipient),
                ).to.eventually.be.true;
              });
            });
          }
        });
      }
    });
  }
});

const doConfidentialTransferOmnibus = (
  token: any,
  transferFrom: boolean,
  withCallback: boolean,
  withProof: boolean,
  args: any[],
): any => {
  const functionSignature = transferFrom
    ? withCallback
      ? withProof
        ? 'confidentialTransferFromAndCallOmnibus(address,address,bytes32,bytes32,bytes32,bytes,bytes)'
        : 'confidentialTransferFromAndCallOmnibus(address,address,bytes32,bytes32,bytes32,bytes)'
      : withProof
      ? 'confidentialTransferFromOmnibus(address,address,bytes32,bytes32,bytes32,bytes)'
      : 'confidentialTransferFromOmnibus(address,address,bytes32,bytes32,bytes32)'
    : withCallback
    ? withProof
      ? 'confidentialTransferAndCallOmnibus(address,bytes32,bytes32,bytes32,bytes,bytes)'
      : 'confidentialTransferAndCallOmnibus(address,bytes32,bytes32,bytes32,bytes)'
    : withProof
    ? 'confidentialTransferOmnibus(address,bytes32,bytes32,bytes32,bytes)'
    : 'confidentialTransferOmnibus(address,bytes32,bytes32,bytes32)';

  return token[functionSignature](...args);
};
