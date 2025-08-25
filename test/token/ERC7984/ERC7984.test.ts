import { $ERC7984Mock } from '../../../types/contracts-exposed/mocks/token/ERC7984Mock.sol/$ERC7984Mock';
import { shouldBehaveLikeERC7984 } from './ERC7984.behaviour';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

/* eslint-disable no-unexpected-multiline */
describe('ERC7984', function () {
  async function deployFixture() {
    const [holder, recipient, operator, anyone] = await ethers.getSigners();
    const token = (await ethers.deployContract('$ERC7984Mock', [name, symbol, uri])) as any as $ERC7984Mock;
    const encryptedInput = await fhevm
      .createEncryptedInput(await token.getAddress(), holder.address)
      .add64(1000)
      .encrypt();
    await token
      .connect(holder)
      ['$_mint(address,bytes32,bytes)'](holder, encryptedInput.handles[0], encryptedInput.inputProof);
    return { token, holder, recipient, operator, anyone };
  }

  shouldBehaveLikeERC7984(deployFixture);
});
/* eslint-enable no-unexpected-multiline */
