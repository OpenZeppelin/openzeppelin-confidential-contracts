import { shouldBehaveLikeVestingConfidential } from './VestingWalletConfidential.behavior';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';

describe('VestingWalletConfidential', function () {
  beforeEach(async function () {
    const accounts = (await ethers.getSigners()).slice(3);
    const [holder, recipient] = accounts;

    const token = await ethers.deployContract('$ERC7984Mock', [name, symbol, uri]);

    const encryptedInput = await fhevm
      .createEncryptedInput(await token.getAddress(), holder.address)
      .add64(1000)
      .encrypt();

    const currentTime = await time.latest();
    const schedule = [currentTime + 60, currentTime + 60 * 61];
    const vesting = await ethers.deployContract('$VestingWalletConfidentialMock', [
      recipient,
      currentTime + 60,
      60 * 60 /* 1 hour */,
    ]);

    await (token as any)
      .connect(holder)
      ['$_mint(address,bytes32,bytes)'](vesting.target, encryptedInput.handles[0], encryptedInput.inputProof);

    Object.assign(this, { accounts, holder, recipient, token, vesting, schedule, vestingAmount: 1000 });
  });

  shouldBehaveLikeVestingConfidential();
});
