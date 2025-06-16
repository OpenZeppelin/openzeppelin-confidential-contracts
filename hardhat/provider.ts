import { extendProvider } from 'hardhat/config';
import { ProviderWrapper } from 'hardhat/plugins';
import type { EIP1193Provider, RequestArguments } from 'hardhat/types';

interface Test {
  request: EIP1193Provider['request'];
}

class CustomProvider extends ProviderWrapper implements Test {
  public lastBlockSnapshot: number;
  public lastCounterRand: number;
  public lastBlockSnapshotForDecrypt: number;

  constructor(protected readonly _wrappedProvider: EIP1193Provider) {
    super(_wrappedProvider);
    this.lastBlockSnapshot = 0;
    this.lastCounterRand = 0;
    this.lastBlockSnapshotForDecrypt = 0;
  }

  async request(args: RequestArguments): ReturnType<EIP1193Provider['request']> {
    switch (args.method) {
      case 'evm_revert': {
        const result = await this._wrappedProvider.request(args);
        this.lastBlockSnapshot = this.lastBlockSnapshotForDecrypt = await (
          this._wrappedProvider.request({ method: 'eth_blockNumber' }) as Promise<string>
        ).then(parseInt);
        this.lastCounterRand = (await this._wrappedProvider.request({
          method: 'eth_call',
          params: [{ to: '0x000000000000000000000000000000000000005d', data: '0x1f20d85c' }, 'latest'],
        })) as number;
        return result;
      }
      case 'get_lastBlockSnapshot':
        return [this.lastBlockSnapshot, this.lastCounterRand];

      case 'get_lastBlockSnapshotForDecrypt':
        return this.lastBlockSnapshotForDecrypt;

      case 'set_lastBlockSnapshot':
        return (this.lastBlockSnapshot = Array.isArray(args.params!) && args.params[0]);

      case 'set_lastBlockSnapshotForDecrypt':
        return (this.lastBlockSnapshotForDecrypt = Array.isArray(args.params!) && args.params[0]);

      default:
        return this._wrappedProvider.request(args);
    }
  }
}

extendProvider(async provider => new CustomProvider(provider));
