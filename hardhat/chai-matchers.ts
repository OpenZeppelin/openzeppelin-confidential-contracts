import { FhevmType } from '@fhevm/hardhat-plugin';
import { buildAssert } from '@nomicfoundation/hardhat-chai-matchers/utils';
import { use } from 'chai';
import { Addressable, BaseContract, BaseContractMethod, BigNumberish, TransactionResponse, ethers } from 'ethers';

/**
 * ERC-7984 counterparts of the `changeTokenBalance` and `changeTokenBalances` matchers from
 * `@nomicfoundation/hardhat-chai-matchers`:
 *
 * ```ts
 * await expect(tx).to.changeConfidentialBalance(token, holder, -100);
 * await expect(tx).to.changeConfidentialBalances(token, [holder, recipient], [-100, 100]);
 * ```
 *
 * Balance handles are read at the block of the transaction and at the previous one, then decrypted with
 * `fhevm.debugger`, which bypasses the ACL. Only available on the cleartext FHEVM network.
 */

const CHANGE_CONFIDENTIAL_BALANCE_MATCHER = 'changeConfidentialBalance';
const CHANGE_CONFIDENTIAL_BALANCES_MATCHER = 'changeConfidentialBalances';

// Chai flag the hardhat-chai-matchers async matchers use to refuse being chained (not exported by the package)
const PREVIOUS_MATCHER_NAME = 'previousMatcherName';

type ConfidentialToken = BaseContract & {
  confidentialBalanceOf: BaseContractMethod<[string], string, string>;
  name: BaseContractMethod<[], string, string>;
  symbol: BaseContractMethod<[], string, string>;
};

type Transaction = TransactionResponse | Promise<TransactionResponse>;

declare global {
  namespace Chai {
    interface Assertion {
      changeConfidentialBalance(
        token: BaseContract,
        account: Addressable | string,
        balanceChange: BigNumberish | ((change: bigint) => boolean),
      ): AsyncAssertion;
      changeConfidentialBalances(
        token: BaseContract,
        accounts: (Addressable | string)[],
        balanceChanges: BigNumberish[] | ((changes: bigint[]) => boolean),
      ): AsyncAssertion;
    }
  }
}

use(function (chai, chaiUtils) {
  supportChangeConfidentialBalance(chai.Assertion, chaiUtils);
});

function supportChangeConfidentialBalance(Assertion: Chai.AssertionStatic, chaiUtils: Chai.ChaiUtils) {
  Assertion.addMethod(
    CHANGE_CONFIDENTIAL_BALANCE_MATCHER,
    function (
      this: any,
      token: ConfidentialToken,
      account: Addressable | string,
      balanceChange: BigNumberish | ((change: bigint) => boolean),
    ) {
      // capture negated flag before async code executes; see buildAssert's jsdoc
      const negated = chaiUtils.flag(this, 'negate');
      const object = chaiUtils.flag(this, 'object');

      // checked before invoking a callback subject, so that a rejected assertion doesn't send a transaction
      preventAsyncMatcherChaining(this, CHANGE_CONFIDENTIAL_BALANCE_MATCHER, chaiUtils);

      validateInput(object, token, CHANGE_CONFIDENTIAL_BALANCE_MATCHER);

      const subject: Transaction = typeof object === 'function' ? object() : object;

      const checkBalanceChange = ([actualChange, address, tokenDescription]: [bigint, string, string]) => {
        const assert = buildAssert(negated, checkBalanceChange);

        if (typeof balanceChange === 'function') {
          assert(
            balanceChange(actualChange),
            `Expected the confidential balance of ${tokenDescription} tokens for "${address}" to satisfy the predicate, but it didn't (confidential balance change: ${actualChange})`,
            `Expected the confidential balance of ${tokenDescription} tokens for "${address}" to NOT satisfy the predicate, but it did (confidential balance change: ${actualChange})`,
          );
        } else {
          assert(
            actualChange === ethers.toBigInt(balanceChange),
            `Expected the confidential balance of ${tokenDescription} tokens for "${address}" to change by ${balanceChange}, but it changed by ${actualChange}`,
            `Expected the confidential balance of ${tokenDescription} tokens for "${address}" NOT to change by ${balanceChange}, but it did`,
          );
        }
      };

      const derivedPromise = Promise.all([
        getConfidentialBalanceChange(subject, token, account),
        getAddressOf(account),
        getTokenDescription(token),
      ]).then(checkBalanceChange);

      this.then = derivedPromise.then.bind(derivedPromise);
      this.catch = derivedPromise.catch.bind(derivedPromise);

      return this;
    },
  );

  Assertion.addMethod(
    CHANGE_CONFIDENTIAL_BALANCES_MATCHER,
    function (
      this: any,
      token: ConfidentialToken,
      accounts: (Addressable | string)[],
      balanceChanges: BigNumberish[] | ((changes: bigint[]) => boolean),
    ) {
      // capture negated flag before async code executes; see buildAssert's jsdoc
      const negated = chaiUtils.flag(this, 'negate');
      const object = chaiUtils.flag(this, 'object');

      // checked before invoking a callback subject, so that a rejected assertion doesn't send a transaction
      preventAsyncMatcherChaining(this, CHANGE_CONFIDENTIAL_BALANCES_MATCHER, chaiUtils);

      validateInput(object, token, CHANGE_CONFIDENTIAL_BALANCES_MATCHER, accounts, balanceChanges);

      const subject: Transaction = typeof object === 'function' ? object() : object;

      const balanceChangesPromise = Promise.all(
        accounts.map(account => getConfidentialBalanceChange(subject, token, account)),
      );
      const addressesPromise = Promise.all(accounts.map(getAddressOf));

      const checkBalanceChanges = ([actualChanges, addresses, tokenDescription]: [bigint[], string[], string]) => {
        const assert = buildAssert(negated, checkBalanceChanges);

        if (typeof balanceChanges === 'function') {
          assert(
            balanceChanges(actualChanges),
            `Expected the confidential balance changes of ${tokenDescription} to satisfy the predicate, but they didn't (confidential balance changes: ${actualChanges.join(
              ', ',
            )})`,
            `Expected the confidential balance changes of ${tokenDescription} to NOT satisfy the predicate, but they did (confidential balance changes: ${actualChanges.join(
              ', ',
            )})`,
          );
        } else {
          assert(
            actualChanges.every((change, i) => change === ethers.toBigInt(balanceChanges[i])),
            `Expected the confidential balances of ${tokenDescription} tokens for ${addresses.join(
              ', ',
            )} to change by ${balanceChanges.join(', ')}, respectively, but they changed by ${actualChanges.join(
              ', ',
            )}`,
            `Expected the confidential balances of ${tokenDescription} tokens for ${addresses.join(
              ', ',
            )} NOT to change by ${balanceChanges.join(', ')}, respectively, but they did`,
          );
        }
      };

      const derivedPromise = Promise.all([balanceChangesPromise, addressesPromise, getTokenDescription(token)]).then(
        checkBalanceChanges,
      );

      this.then = derivedPromise.then.bind(derivedPromise);
      this.catch = derivedPromise.catch.bind(derivedPromise);

      return this;
    },
  );
}

function validateInput(
  subject: unknown,
  token: unknown,
  method: string,
  accounts?: (Addressable | string)[],
  balanceChanges?: BigNumberish[] | ((changes: bigint[]) => boolean),
) {
  try {
    checkToken(token, method);

    if (accounts !== undefined && !Array.isArray(accounts)) {
      throw new Error(`The second argument of ${method} must be an array of accounts`);
    }

    if (Array.isArray(balanceChanges) && accounts!.length !== balanceChanges.length) {
      throw new Error(
        `The number of accounts (${accounts!.length}) is different than the number of expected balance changes (${
          balanceChanges.length
        })`,
      );
    }
  } catch (e) {
    // if the input validation fails, we discard the subject since it could
    // potentially be a rejected promise
    Promise.resolve(subject).catch(() => {});
    throw e;
  }
}

function checkToken(token: unknown, method: string) {
  if (typeof token !== 'object' || token === null || !('interface' in token)) {
    throw new Error(`The first argument of ${method} must be the contract instance of the token`);
  } else if ((token as BaseContract).interface.getFunction('confidentialBalanceOf') === null) {
    throw new Error('The given contract instance is not an ERC7984 token');
  }
}

/**
 * Async matchers resolve through the `then` they set on the assertion, so chaining two of them would replace the
 * first one's promise and silently skip its check. Throws if an async matcher already ran on the assertion, and
 * sets the flag the hardhat-chai-matchers check so that theirs refuse to run after this one.
 */
function preventAsyncMatcherChaining(assertion: any, matcherName: string, chaiUtils: Chai.ChaiUtils) {
  if (assertion.then !== undefined) {
    const previousMatcherName = chaiUtils.flag(assertion, PREVIOUS_MATCHER_NAME);
    throw new Error(
      `The matcher '${matcherName}' cannot be chained after ${
        previousMatcherName === undefined ? 'another async matcher' : `'${previousMatcherName}'`
      }`,
    );
  }

  chaiUtils.flag(assertion, PREVIOUS_MATCHER_NAME, matcherName);
}

async function getConfidentialBalanceChange(
  transaction: Transaction,
  token: ConfidentialToken,
  account: Addressable | string,
): Promise<bigint> {
  // `hardhat` can't be imported while the config is being loaded, so it is resolved lazily
  const { fhevm } = await import('hardhat');

  const txResponse = await transaction;

  const txReceipt = await txResponse.wait();
  assertIsNotNull(txReceipt, 'txReceipt');
  const txBlockNumber = txReceipt.blockNumber;

  const block = await txReceipt.getBlock();
  if (block.transactions.length !== 1) {
    throw new Error('Multiple transactions found in block');
  }

  const address = await getAddressOf(account);

  // uninitialized balances have no handle to decrypt
  const decrypt = (handle: string) =>
    handle === ethers.ZeroHash ? 0n : fhevm.debugger.decryptEuint(FhevmType.euint64, handle);

  const balanceAfter = await token.confidentialBalanceOf(address, { blockTag: txBlockNumber }).then(decrypt);

  const balanceBefore = await token.confidentialBalanceOf(address, { blockTag: txBlockNumber - 1 }).then(decrypt);

  return balanceAfter - balanceBefore;
}

async function getAddressOf(account: Addressable | string): Promise<string> {
  return ethers.resolveAddress(account);
}

function assertIsNotNull<T>(value: T, valueName: string): asserts value is Exclude<T, null> {
  if (value === null) {
    throw new Error(`${valueName} should not be null`);
  }
}

const tokenDescriptionsCache: Record<string, string> = {};
/**
 * Get a description for the given token. Use the symbol of the token if
 * possible; if it doesn't exist, the name is used; if the name doesn't
 * exist, the address of the token is used.
 */
async function getTokenDescription(token: ConfidentialToken): Promise<string> {
  const tokenAddress = await token.getAddress();
  if (tokenDescriptionsCache[tokenAddress] === undefined) {
    let tokenDescription = `<token at ${tokenAddress}>`;
    try {
      tokenDescription = await token.symbol();
    } catch {
      try {
        tokenDescription = await token.name();
      } catch {}
    }

    tokenDescriptionsCache[tokenAddress] = tokenDescription;
  }

  return tokenDescriptionsCache[tokenAddress];
}
