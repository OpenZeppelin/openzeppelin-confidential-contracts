import { ethers, ContractTransactionResponse, EventLog, ContractTransactionReceipt, Contract, Log } from 'ethers';

export async function callAndGetResult(txPromise: Promise<ContractTransactionResponse>, eventName: string) {
  const receipt = (await txPromise.then(tx => tx.wait()))!;
  return ((await getResult(receipt, receipt.to!, eventName)) as EventLog).args;
}

export async function callAndGetResultFromEmitter(
  txPromise: Promise<ContractTransactionResponse>,
  emitter: Contract,
  eventName: string,
) {
  const receipt = await txPromise.then(tx => tx.wait());
  const log = await getResult(receipt!, emitter.target as string, eventName);
  return emitter.interface.parseLog(log)!.args;
}

async function getResult(
  receipt: ContractTransactionReceipt,
  emitter: string,
  eventName: string,
): Promise<Log | EventLog> {
  const logs = receipt?.logs.filter(log => log.address == emitter && log.topics[0] == ethers.id(eventName));
  return logs![0];
}
