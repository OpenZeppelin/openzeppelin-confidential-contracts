import { awaitAllDecryptionResults, initGateway } from '../../_template/asyncDecrypt';
import { createInstance } from '../../_template/instance';
import { reencryptEuint64 } from '../../_template/reencrypt';
import { impersonate } from '../../helpers/accounts';
import { expect } from 'chai';
import hre, { ethers } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';
const gatewayAddress = '0x33347831500F1e73f0ccCBb95c9f86B94d7b1123';

/* eslint-disable no-unexpected-multiline */
describe('ConfidentialFungibleTokenWrapper', function () {
  beforeEach(async function () {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const token = await ethers.deployContract('$ERC20Mock', ['Public Token', 'PT', 18]);
    const wrapper = await ethers.deployContract('ConfidentialFungibleTokenERC20WrapperMock', [
      token,
      name,
      symbol,
      uri,
    ]);

    this.fhevm = await createInstance();
    this.accounts = accounts.slice(3);
    this.holder = holder;
    this.recipient = recipient;
    this.token = token;
    this.operator = operator;
    this.wrapper = wrapper;

    await this.token.$_mint(this.holder.address, ethers.parseUnits('1000', 18));
    await this.token.connect(this.holder).approve(this.wrapper, ethers.MaxUint256);
  });

  describe('Wrap', async function () {
    for (const viaCallback of [false, true]) {
      describe(`via ${viaCallback ? 'callback' : 'transfer from'}`, function () {
        it('with multiple of rate', async function () {
          const amountToWrap = ethers.parseUnits('100', 18);

          if (viaCallback) {
            await this.token.connect(this.holder).transferAndCall(this.wrapper, amountToWrap);
          } else {
            await this.wrapper.connect(this.holder).wrap(this.holder.address, amountToWrap);
          }

          await expect(this.token.balanceOf(this.holder)).to.eventually.equal(ethers.parseUnits('900', 18));
          const wrappedBalanceHandle = await this.wrapper.balanceOf(this.holder.address);
          await expect(
            reencryptEuint64(this.holder, this.fhevm, wrappedBalanceHandle, this.wrapper.target),
          ).to.eventually.equal(ethers.parseUnits('100', 9));
        });

        it('with non-multiple of rate', async function () {
          const amountToWrap = ethers.parseUnits('101', 8);

          if (viaCallback) {
            await this.token.connect(this.holder).transferAndCall(this.wrapper, amountToWrap);
          } else {
            await this.wrapper.connect(this.holder).wrap(this.holder.address, amountToWrap);
          }

          await expect(this.token.balanceOf(this.holder)).to.eventually.equal(
            ethers.parseUnits('1000', 18) - ethers.parseUnits('10', 9),
          );
          const wrappedBalanceHandle = await this.wrapper.balanceOf(this.holder.address);
          await expect(
            reencryptEuint64(this.holder, this.fhevm, wrappedBalanceHandle, this.wrapper.target),
          ).to.eventually.equal(10);
        });

        if (viaCallback) {
          it('to another address', async function () {
            const amountToWrap = ethers.parseUnits('100', 18);

            await this.token
              .connect(this.holder)
              ['transferAndCall(address,uint256,bytes)'](
                this.wrapper,
                amountToWrap,
                ethers.solidityPacked(['address'], [this.recipient.address]),
              );

            await expect(this.token.balanceOf(this.holder)).to.eventually.equal(ethers.parseUnits('900', 18));
            const wrappedBalanceHandle = await this.wrapper.balanceOf(this.recipient.address);
            await expect(
              reencryptEuint64(this.recipient, this.fhevm, wrappedBalanceHandle, this.wrapper.target),
            ).to.eventually.equal(ethers.parseUnits('100', 9));
          });

          it('from unauthorized caller', async function () {
            await expect(this.wrapper.connect(this.holder).onTransferReceived(this.holder, this.holder, 100, '0x'))
              .to.be.revertedWithCustomError(this.wrapper, 'ConfidentialFungibleTokenUnauthorizedCaller')
              .withArgs(this.holder.address);
          });
        }
      });
    }
  });

  describe('Unwrap', async function () {
    beforeEach(async function () {
      const amountToWrap = ethers.parseUnits('100', 18);
      await this.token.connect(this.holder).transferAndCall(this.wrapper, amountToWrap);

      await initGateway();
    });

    it('less than balance', async function () {
      const withdrawalAmount = ethers.parseUnits('10', 9);
      const input = this.fhevm.createEncryptedInput(this.wrapper.target, this.holder.address);
      input.add64(withdrawalAmount);
      const encryptedInput = await input.encrypt();

      await this.wrapper
        .connect(this.holder)
        ['unwrap(address,address,bytes32,bytes)'](
          this.holder,
          this.holder,
          encryptedInput.handles[0],
          encryptedInput.inputProof,
        );

      // wait for gateway to process the request
      await awaitAllDecryptionResults();

      await expect(this.token.balanceOf(this.holder)).to.eventually.equal(
        withdrawalAmount * 10n ** 9n + ethers.parseUnits('900', 18),
      );
    });

    it('unwrap full balance', async function () {
      await this.wrapper
        .connect(this.holder)
        .unwrap(this.holder, this.holder, await this.wrapper.balanceOf(this.holder.address));
      await awaitAllDecryptionResults();

      await expect(this.token.balanceOf(this.holder)).to.eventually.equal(ethers.parseUnits('1000', 18));
    });

    it('more than balance', async function () {
      const withdrawalAmount = ethers.parseUnits('101', 9);
      const input = this.fhevm.createEncryptedInput(this.wrapper.target, this.holder.address);
      input.add64(withdrawalAmount);
      const encryptedInput = await input.encrypt();

      await this.wrapper
        .connect(this.holder)
        ['unwrap(address,address,bytes32,bytes)'](
          this.holder,
          this.holder,
          encryptedInput.handles[0],
          encryptedInput.inputProof,
        );

      await awaitAllDecryptionResults();
      await expect(this.token.balanceOf(this.holder)).to.eventually.equal(ethers.parseUnits('900', 18));
    });

    it('to invalid recipient', async function () {
      const withdrawalAmount = ethers.parseUnits('10', 9);
      const input = this.fhevm.createEncryptedInput(this.wrapper.target, this.holder.address);
      input.add64(withdrawalAmount);
      const encryptedInput = await input.encrypt();

      await expect(
        this.wrapper
          .connect(this.holder)
          ['unwrap(address,address,bytes32,bytes)'](
            this.holder,
            ethers.ZeroAddress,
            encryptedInput.handles[0],
            encryptedInput.inputProof,
          ),
      )
        .to.be.revertedWithCustomError(this.wrapper, 'ConfidentialFungibleTokenInvalidReceiver')
        .withArgs(ethers.ZeroAddress);
    });

    it('via an approved operator', async function () {
      const withdrawalAmount = ethers.parseUnits('100', 9);
      const input = this.fhevm.createEncryptedInput(this.wrapper.target, this.operator.address);
      input.add64(withdrawalAmount);
      const encryptedInput = await input.encrypt();

      await this.wrapper.connect(this.holder).setOperator(this.operator.address, Math.round(Date.now() / 1000) + 1000);

      await this.wrapper
        .connect(this.operator)
        ['unwrap(address,address,bytes32,bytes)'](
          this.holder,
          this.holder,
          encryptedInput.handles[0],
          encryptedInput.inputProof,
        );

      // wait for gateway to process the request
      await awaitAllDecryptionResults();

      await expect(this.token.balanceOf(this.holder)).to.eventually.equal(ethers.parseUnits('1000', 18));
    });

    it('via an unapproved operator', async function () {
      const withdrawalAmount = ethers.parseUnits('100', 9);
      const input = this.fhevm.createEncryptedInput(this.wrapper.target, this.operator.address);
      input.add64(withdrawalAmount);
      const encryptedInput = await input.encrypt();

      await expect(
        this.wrapper
          .connect(this.operator)
          ['unwrap(address,address,bytes32,bytes)'](
            this.holder,
            this.holder,
            encryptedInput.handles[0],
            encryptedInput.inputProof,
          ),
      )
        .to.be.revertedWithCustomError(this.wrapper, 'ConfidentialFungibleTokenUnauthorizedSpender')
        .withArgs(this.holder, this.operator);
    });

    it('with a value not allowed to sender', async function () {
      const totalSupplyHandle = await this.wrapper.totalSupply();

      await expect(this.wrapper.connect(this.holder).unwrap(this.holder, this.holder, totalSupplyHandle))
        .to.be.revertedWithCustomError(this.wrapper, 'ConfidentialFungibleTokenUnauthorizedUseOfEncryptedAmount')
        .withArgs(totalSupplyHandle, this.holder);
    });

    it('finalized not by gateway', async function () {
      await expect(this.wrapper.connect(this.holder).finalizeUnwrap(12, 12))
        .to.be.revertedWithCustomError(this.wrapper, 'ConfidentialFungibleTokenUnauthorizedCaller')
        .withArgs(this.holder);
    });

    it('finalized for an invalid request id', async function () {
      await impersonate(hre, gatewayAddress);
      const gatewaySigner = await ethers.getSigner(gatewayAddress);

      await expect(this.wrapper.connect(gatewaySigner).finalizeUnwrap(12, 12))
        .to.be.revertedWithCustomError(this.wrapper, 'ConfidentialFungibleTokenInvalidGatewayRequest')
        .withArgs(12);
    });
  });

  describe('Initialization', function () {
    describe('decimals', function () {
      it('when underlying has 9 decimals', async function () {
        const token = await ethers.deployContract('ERC20Mock', ['Public Token', 'PT', 9]);
        const wrapper = await ethers.deployContract('ConfidentialFungibleTokenERC20WrapperMock', [
          token,
          name,
          symbol,
          uri,
        ]);

        await expect(wrapper.decimals()).to.eventually.equal(9);
        await expect(wrapper.rate()).to.eventually.equal(1);
      });

      it('when underlying has more than 9 decimals', async function () {
        const token = await ethers.deployContract('ERC20Mock', ['Public Token', 'PT', 18]);
        const wrapper = await ethers.deployContract('ConfidentialFungibleTokenERC20WrapperMock', [
          token,
          name,
          symbol,
          uri,
        ]);

        await expect(wrapper.decimals()).to.eventually.equal(9);
        await expect(wrapper.rate()).to.eventually.equal(10n ** 9n);
      });

      it('when underlying has less than 9 decimals', async function () {
        const token = await ethers.deployContract('ERC20Mock', ['Public Token', 'PT', 8]);
        const wrapper = await ethers.deployContract('ConfidentialFungibleTokenERC20WrapperMock', [
          token,
          name,
          symbol,
          uri,
        ]);

        await expect(wrapper.decimals()).to.eventually.equal(8);
        await expect(wrapper.rate()).to.eventually.equal(1);
      });

      it('when underlying decimals are not available', async function () {
        const token = await ethers.deployContract('ERC20RevertDecimalsMock');
        const wrapper = await ethers.deployContract('ConfidentialFungibleTokenERC20WrapperMock', [
          token,
          name,
          symbol,
          uri,
        ]);

        await expect(wrapper.decimals()).to.eventually.equal(9);
        await expect(wrapper.rate()).to.eventually.equal(10n ** 9n);
      });

      it('when decimals are over `type(uint8).max`', async function () {
        const token = await ethers.deployContract('ERC20ExcessDecimalsMock');
        await expect(ethers.deployContract('ConfidentialFungibleTokenERC20WrapperMock', [token, name, symbol, uri])).to
          .be.reverted;
      });
    });
  });
});
/* eslint-disable no-unexpected-multiline */
