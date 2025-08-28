import { $ERC7984Mock } from '../../../types/contracts-exposed/mocks/token/ERC7984Mock.sol/$ERC7984Mock';
import { shouldBehaveLikeERC7984 } from './ERC7984.behaviour';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const contract = '$ERC7984Mock';
const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

async function deployFixture(_contract?: string, extraDeploymentArgs: any[] = []) {
  const [holder, recipient, operator, anyone] = await ethers.getSigners();
  const token = (await ethers.deployContract(_contract ? _contract : contract, [
    name,
    symbol,
    uri,
    ...extraDeploymentArgs,
  ])) as any as $ERC7984Mock;
  const encryptedInput = await fhevm
    .createEncryptedInput(await token.getAddress(), holder.address)
    .add64(1000)
    .encrypt();
  await token
    .connect(holder)
    ['$_mint(address,bytes32,bytes)'](holder, encryptedInput.handles[0], encryptedInput.inputProof);
  return { token, holder, recipient, operator, anyone };
}

describe('ERC7984', function () {
  describe('mint', function () {
    for (const existingUser of [false, true]) {
      it(`to ${existingUser ? 'existing' : 'new'} user`, async function () {
        const { token, holder } = await deployFixture();
        if (existingUser) {
          const encryptedInput = await fhevm
            .createEncryptedInput(await token.getAddress(), holder.address)
            .add64(1000)
            .encrypt();

          await token
            .connect(holder)
            ['$_mint(address,bytes32,bytes)'](holder, encryptedInput.handles[0], encryptedInput.inputProof);
        }

        const balanceOfHandleHolder = await token.confidentialBalanceOf(holder);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, await token.getAddress(), holder),
        ).to.eventually.equal(existingUser ? 2000 : 1000);

        // Check total supply
        const totalSupplyHandle = await token.confidentialTotalSupply();
        await token.connect(holder).confidentialTotalSupplyAccess();
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, totalSupplyHandle, await token.getAddress(), holder),
        ).to.eventually.equal(existingUser ? 2000 : 1000);
      });
    }

    it('from zero address', async function () {
      const { token, holder } = await deployFixture();
      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), holder.address)
        .add64(400)
        .encrypt();

      await expect(
        token
          .connect(holder)
          ['$_mint(address,bytes32,bytes)'](ethers.ZeroAddress, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(token, 'ERC7984InvalidReceiver')
        .withArgs(ethers.ZeroAddress);
    });
  });

  describe('burn', function () {
    for (const sufficientBalance of [false, true]) {
      it(`from a user with ${sufficientBalance ? 'sufficient' : 'insufficient'} balance`, async function () {
        const { token, holder } = await deployFixture();
        const burnAmount = sufficientBalance ? 400 : 1100;

        const encryptedInput = await fhevm
          .createEncryptedInput(await token.getAddress(), holder.address)
          .add64(burnAmount)
          .encrypt();

        await token
          .connect(holder)
          ['$_burn(address,bytes32,bytes)'](holder, encryptedInput.handles[0], encryptedInput.inputProof);

        const balanceOfHandleHolder = await token.confidentialBalanceOf(holder);
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, balanceOfHandleHolder, await token.getAddress(), holder),
        ).to.eventually.equal(sufficientBalance ? 600 : 1000);

        // Check total supply
        const totalSupplyHandle = await token.confidentialTotalSupply();
        await token.connect(holder).confidentialTotalSupplyAccess();
        await expect(
          fhevm.userDecryptEuint(FhevmType.euint64, totalSupplyHandle, await token.getAddress(), holder),
        ).to.eventually.equal(sufficientBalance ? 600 : 1000);
      });
    }

    it('from zero address', async function () {
      const { token, holder } = await deployFixture();
      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), holder.address)
        .add64(400)
        .encrypt();

      await expect(
        token
          .connect(holder)
          ['$_burn(address,bytes32,bytes)'](ethers.ZeroAddress, encryptedInput.handles[0], encryptedInput.inputProof),
      )
        .to.be.revertedWithCustomError(token, 'ERC7984InvalidSender')
        .withArgs(ethers.ZeroAddress);
    });
  });

  describe('disclose', function () {
    let [holder, recipient]: HardhatEthersSigner[] = [];
    let token: $ERC7984Mock;
    let expectedAmount: any;
    let expectedHandle: any;
    beforeEach(async function () {
      ({ token, holder, recipient } = await deployFixture());
      expectedAmount = undefined;
      expectedHandle = undefined;
    });

    it('user balance', async function () {
      const holderBalanceHandle = await token.confidentialBalanceOf(holder);

      await token.connect(holder).discloseEncryptedAmount(holderBalanceHandle);

      expectedAmount = 1000n;
      expectedHandle = holderBalanceHandle;
    });

    it('transaction amount', async function () {
      const encryptedInput = await fhevm
        .createEncryptedInput(await token.getAddress(), holder.address)
        .add64(400)
        .encrypt();

      const tx = await token['confidentialTransfer(address,bytes32,bytes)'](
        recipient,
        encryptedInput.handles[0],
        encryptedInput.inputProof,
      );

      const transferEvent = (await tx.wait()).logs.filter((log: any) => log.address === token.target)[0];
      const transferAmount = transferEvent.args[2];

      await token.connect(recipient).discloseEncryptedAmount(transferAmount);

      expectedAmount = 400n;
      expectedHandle = transferAmount;
    });

    it("other user's balance", async function () {
      const holderBalanceHandle = await token.confidentialBalanceOf(holder);

      await expect(token.connect(recipient).discloseEncryptedAmount(holderBalanceHandle))
        .to.be.revertedWithCustomError(token, 'ERC7984UnauthorizedUseOfEncryptedAmount')
        .withArgs(holderBalanceHandle, recipient);
    });

    it('invalid signature reverts', async function () {
      const holderBalanceHandle = await token.confidentialBalanceOf(holder);
      await token.connect(holder).discloseEncryptedAmount(holderBalanceHandle);

      await expect(token.connect(holder).finalizeDiscloseEncryptedAmount(0, 0, [])).to.be.reverted;
    });

    afterEach(async function () {
      if (expectedHandle === undefined || expectedAmount === undefined) return;

      await fhevm.awaitDecryptionOracle();

      // Check that event was correctly emitted
      const eventFilter = token.filters.AmountDisclosed();
      const discloseEvent = (await token.queryFilter(eventFilter))[0];
      expect(discloseEvent.args[0]).to.equal(expectedHandle);
      expect(discloseEvent.args[1]).to.equal(expectedAmount);
    });
  });

  shouldBehaveLikeERC7984(contract);
});

export { deployFixture as deployERC7984Fixture };
