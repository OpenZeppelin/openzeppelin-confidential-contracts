import { VestingWalletCliffExecutorConfidential__factory } from '../../types';
import { $VestingWalletConfidentialFactory } from '../../types/contracts-exposed/finance/VestingWalletConfidentialFactory.sol/$VestingWalletConfidentialFactory';
import { $ConfidentialFungibleTokenMock } from '../../types/contracts-exposed/mocks/token/ConfidentialFungibleTokenMock.sol/$ConfidentialFungibleTokenMock';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { days } from '@nomicfoundation/hardhat-network-helpers/dist/src/helpers/time/duration';
import { expect } from 'chai';
import { ethers, fhevm } from 'hardhat';

const name = 'ConfidentialFungibleToken';
const symbol = 'CFT';
const uri = 'https://example.com/metadata';
const startTimestamp = 9876543210;
const duration = 1234;
const cliff = 10;
let factory: $VestingWalletConfidentialFactory;

describe('VestingWalletConfidentialFactory', function () {
  beforeEach(async function () {
    const accounts = (await ethers.getSigners()).slice(5);
    const [holder, recipient, recipient2, operator, executor] = accounts;

    const token = (await ethers.deployContract('$ConfidentialFungibleTokenMock', [
      name,
      symbol,
      uri,
    ])) as any as $ConfidentialFungibleTokenMock;

    const encryptedInput = await fhevm
      .createEncryptedInput(await token.getAddress(), holder.address)
      .add64(1000)
      .encrypt();

    const currentTime = await time.latest();
    const schedule = [currentTime + 60, currentTime + 60 * 121];
    factory = (await ethers.deployContract(
      '$VestingWalletConfidentialFactoryMock',
      [],
    )) as unknown as $VestingWalletConfidentialFactory;

    await token
      .connect(holder)
      ['$_mint(address,bytes32,bytes)'](holder.address, encryptedInput.handles[0], encryptedInput.inputProof)
      .then(tx => tx.wait());
    const until = (await time.latest()) + days(1);
    await expect(
      await token
        .connect(holder)
        .setOperator(await factory.getAddress(), until)
        .then(tx => tx.wait()),
    )
      .to.emit(token, 'OperatorSet')
      .withArgs(holder, await factory.getAddress(), until);

    Object.assign(this, {
      accounts,
      holder,
      recipient,
      recipient2,
      operator,
      executor,
      token,
      factory,
      schedule,
      vestingAmount: 1000,
    });
  });

  it('should create vesting wallet with predeterministic address', async function () {
    const predictedVestingWalletAddress = await factory.predictVestingWalletConfidential(
      this.recipient,
      startTimestamp,
      duration,
      cliff,
      this.executor,
    );
    const vestingWalletAddress = await factory.createVestingWalletConfidential.staticCall(
      this.recipient,
      startTimestamp,
      duration,
      cliff,
      this.executor,
    );
    expect(vestingWalletAddress).to.be.equal(predictedVestingWalletAddress);
  });

  it('should create vesting wallet', async function () {
    const vestingWalletAddress = await factory.predictVestingWalletConfidential(
      this.recipient,
      startTimestamp,
      duration,
      cliff,
      this.executor,
    );

    await expect(
      await factory.createVestingWalletConfidential(this.recipient, startTimestamp, duration, cliff, this.executor),
    )
      .to.emit(factory, 'VestingWalletConfidentialCreated')
      .withArgs(this.recipient, vestingWalletAddress, startTimestamp, duration, cliff, this.executor);
    const vestingWallet = VestingWalletCliffExecutorConfidential__factory.connect(
      vestingWalletAddress,
      ethers.provider,
    );
    expect(await vestingWallet.owner()).to.be.equal(this.recipient);
    expect(await vestingWallet.start()).to.be.equal(startTimestamp);
    expect(await vestingWallet.duration()).to.be.equal(duration);
    expect(await vestingWallet.cliff()).to.be.equal(startTimestamp + cliff);
    expect(await vestingWallet.executor()).to.be.equal(this.executor);
  });

  it('should not create vesting wallet twice', async function () {
    await expect(
      await factory.createVestingWalletConfidential(this.recipient, startTimestamp, duration, cliff, this.executor),
    ).to.emit(factory, 'VestingWalletConfidentialCreated');
    await expect(
      factory.createVestingWalletConfidential(this.recipient, startTimestamp, duration, cliff, this.executor),
    ).to.be.revertedWithCustomError(factory, 'FailedDeployment');
  });

  it('should batch funding of vesting wallets', async function () {
    const amount1 = 101;
    const amount2 = 102;
    const encryptedInput = await fhevm
      .createEncryptedInput(await factory.getAddress(), this.holder.address)
      .add64(amount1)
      .add64(amount2)
      .encrypt();
    const vestingWalletAddress1 = await factory.predictVestingWalletConfidential(
      this.recipient,
      startTimestamp,
      duration,
      cliff,
      this.executor,
    );
    const vestingWalletAddress2 = await factory.predictVestingWalletConfidential(
      this.recipient2,
      startTimestamp,
      duration,
      cliff,
      this.executor,
    );

    await expect(
      await factory.connect(this.holder).batchFundVestingWalletConfidential(
        await this.token.getAddress(),
        [
          {
            beneficiary: this.recipient,
            encryptedAmount: encryptedInput.handles[0],
            start: startTimestamp,
            cliff: cliff,
            executor: this.executor,
          },
          {
            beneficiary: this.recipient2,
            encryptedAmount: encryptedInput.handles[1],
            start: startTimestamp,
            cliff: cliff,
            executor: this.executor,
          },
        ],
        duration,
        encryptedInput.inputProof,
      ),
    )
      .to.emit(factory, 'VestingWalletConfidentialBatchFunded')
      .withArgs(this.holder, anyValue)
      //TODO: Check returned value from function & event params
      .to.emit(factory, 'VestingWalletConfidentialFunded')
      .withArgs(
        vestingWalletAddress1,
        this.recipient,
        await this.token.getAddress(),
        anyValue,
        startTimestamp,
        duration,
        cliff,
        this.executor,
      )
      .to.emit(this.token, 'ConfidentialTransfer')
      .withArgs(this.holder, vestingWalletAddress2, anyValue)
      .to.emit(factory, 'VestingWalletConfidentialFunded')
      .withArgs(
        vestingWalletAddress2,
        this.recipient2,
        await this.token.getAddress(),
        anyValue,
        startTimestamp,
        duration,
        cliff,
        this.executor,
      )
      .to.emit(this.token, 'ConfidentialTransfer')
      .withArgs(this.holder, vestingWalletAddress2, anyValue);
    // TODO: Check balances
  });
});
