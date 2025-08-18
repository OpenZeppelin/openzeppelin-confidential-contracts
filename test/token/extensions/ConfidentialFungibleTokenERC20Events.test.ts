import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

describe('ConfidentialFungibleTokenERC20Events', function () {
  beforeEach(async function () {
    const [holder] = await ethers.getSigners();

    const token = await ethers.deployContract('$ConfidentialFungibleTokenERC20EventsMock', [name, symbol, uri]);
    this.token = token;
    this.holder = holder;
  });

  it('should emit ERC20 transfer event', async function () {
    const encryptedInput = await fhevm
      .createEncryptedInput(this.token.target, this.holder.address)
      .add64(100)
      .encrypt();

    await expect(
      this.token
        .connect(this.holder)
        ['$_mint(address,bytes32,bytes)'](this.holder, encryptedInput.handles[0], encryptedInput.inputProof),
    )
      .to.emit(this.token, 'Transfer')
      .withArgs(ethers.ZeroAddress, this.holder.address, 1);
  });
});
