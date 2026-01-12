import { IERC165__factory, IERC7984__factory } from '../../../types';
import { allowHandle } from '../../helpers/accounts';
import { getFunctions, getInterfaceId } from '../../helpers/interface';
import { FhevmType } from '@fhevm/hardhat-plugin';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from 'chai';
import hre, { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

describe('BatcherConfidential', function () {
  beforeEach(async function () {
    const accounts = await ethers.getSigners();
    const [holder, recipient, operator] = accounts;

    const fromTokenUnderlying = await ethers.deployContract('$ERC20Mock', [name, symbol, 18]);
    const toTokenUnderlying = await ethers.deployContract('$ERC20Mock', [name, symbol, 18]);

    const fromToken = await ethers.deployContract('$ERC7984ERC20WrapperMock', [fromTokenUnderlying, name, symbol, uri]);
    const toToken = await ethers.deployContract('$ERC7984ERC20WrapperMock', [toTokenUnderlying, name, symbol, uri]);

    for (const tokens of [
      { underlying: fromTokenUnderlying, wrapper: fromToken },
      { underlying: toTokenUnderlying, wrapper: toToken },
    ]) {
      await tokens.underlying.$_mint(holder, 1000);
      await (tokens.underlying.connect(holder) as any).approve(holder, 1000);
      await tokens.wrapper.wrap(holder, 1000);
    }

    const batcher = await ethers.deployContract('$BatcherConfidentialMock', [fromToken, toToken]);

    Object.assign(this, { fromToken, toToken, accounts: accounts.slice(3), holder, recipient, operator, batcher });
  });

  it.only('Temp test', async function () {
    await this.fromToken.connect(this.holder).setOperator(this.batcher, Math.floor(Date.now() / 1000 + 10_000));

    const encryptedInput = await fhevm
      .createEncryptedInput(this.batcher.target as string, this.holder.address)
      .add64(1000)
      .encrypt();

    await this.batcher.join(encryptedInput.handles[0], encryptedInput.inputProof);
    await this.batcher.dispatchBatch();
  });
});
