import { ContractTransactionResponse, EventLog, Contract, Result } from 'ethers';

/**
 * Returns the args of all `eventName` events emitted by the called contract, in emission order. `eventName` can be
 * either the event name or its full signature.
 */
export async function callAndGetResults(
  txPromise: Promise<ContractTransactionResponse>,
  eventName: string,
): Promise<Result[]> {
  const receipt = (await txPromise.then(tx => tx.wait()))!;
  return receipt.logs
    .filter(
      (log): log is EventLog =>
        log instanceof EventLog &&
        log.address == receipt.to &&
        log.topics[0] == log.interface.getEvent(eventName)?.topicHash,
    )
    .map(log => log.args);
}

/**
 * Returns the args of the first `eventName` event emitted by the called contract. `eventName` can be either the
 * event name or its full signature. Throws if no such event was emitted.
 */
export function callAndGetResult(txPromise: Promise<ContractTransactionResponse>, eventName: string): Promise<Result> {
  return callAndGetResults(txPromise, eventName).then(results => firstResult(results, eventName));
}

/**
 * Returns the args of all `eventName` events emitted by `emitter`, in emission order. `eventName` can be either the
 * event name or its full signature.
 */
export async function callAndGetResultsFromEmitter(
  txPromise: Promise<ContractTransactionResponse>,
  emitter: Contract,
  eventName: string,
): Promise<Result[]> {
  const receipt = (await txPromise.then(tx => tx.wait()))!;
  const { topicHash } = emitter.interface.getEvent(eventName)!;
  return receipt.logs
    .filter(log => log.address == emitter.target && log.topics[0] == topicHash)
    .map(log => emitter.interface.parseLog(log)!.args);
}

/**
 * Returns the args of the first `eventName` event emitted by `emitter`. `eventName` can be either the event name or
 * its full signature. Throws if no such event was emitted.
 */
export function callAndGetResultFromEmitter(
  txPromise: Promise<ContractTransactionResponse>,
  emitter: Contract,
  eventName: string,
): Promise<Result> {
  return callAndGetResultsFromEmitter(txPromise, emitter, eventName).then(results => firstResult(results, eventName));
}

function firstResult(results: Result[], eventName: string): Result {
  if (results.length == 0) throw new Error(`No ${eventName} event emitted`);
  return results[0];
}
