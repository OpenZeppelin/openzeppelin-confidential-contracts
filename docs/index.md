# Solidity API

## IConfidentialFungibleToken

_Draft interface for a confidential fungible token standard utilizing the Zama TFHE library._

### OperatorSet

```solidity
event OperatorSet(address holder, address operator, uint48 until)
```

_Emitted when the `until` timestamp for an operator `operator` is updated for a given `holder`.
The operator may move any amount of tokens on behalf of the holder until the timestamp `until`._

### ConfidentialTransfer

```solidity
event ConfidentialTransfer(address from, address to, euint64 amount)
```

_Emitted when a confidential transfer is made from `from` to `to` of encrypted amount `amount`._

### EncryptedAmountDisclosed

```solidity
event EncryptedAmountDisclosed(euint64 encryptedAmount, uint64 amount)
```

_Emitted when an encrypted amount is disclosed. Accounts with access to the encrypted amount
`encryptedAmount` that is also accessible to this contract should be able to disclose the amount.
This functionality is implementation specific._

### name

```solidity
function name() external view returns (string)
```

_Returns the name of the token._

### symbol

```solidity
function symbol() external view returns (string)
```

_Returns the symbol of the token._

### decimals

```solidity
function decimals() external view returns (uint8)
```

_Returns the number of decimals of the token. Recommended to be 9._

### tokenURI

```solidity
function tokenURI() external view returns (string)
```

_Returns the token URI._

### totalSupply

```solidity
function totalSupply() external view returns (euint64)
```

_Returns the encrypted total supply of the token._

### balanceOf

```solidity
function balanceOf(address account) external view returns (euint64)
```

_Returns the encrypted balance of the account `account`._

### isOperator

```solidity
function isOperator(address holder, address spender) external view returns (bool)
```

_Returns true if `spender` is currently an operator for `holder`._

### setOperator

```solidity
function setOperator(address operator, uint48 until) external
```

_Sets `operator` as an operator for `holder` until the timestamp `until`.

NOTE: An operator may transfer any amount of tokens on behalf of a holder while approved._

### confidentialTransfer

```solidity
function confidentialTransfer(address to, einput encryptedAmount, bytes inputProof) external returns (euint64)
```

_Transfers the encrypted amount `encryptedAmount` to `to` with the given input proof `inputProof`.

Returns the encrypted amount that was actually transferred._

### confidentialTransfer

```solidity
function confidentialTransfer(address to, euint64 amount) external returns (euint64 transferred)
```

_Similar to {confidentialTransfer-address-einput-bytes} but without an input proof. The caller
*must* already be approved by ACL for the given `amount`._

### confidentialTransferFrom

```solidity
function confidentialTransferFrom(address from, address to, einput encryptedAmount, bytes inputProof) external returns (euint64)
```

_Transfers the encrypted amount `encryptedAmount` from `from` to `to` with the given input proof
`inputProof`. `msg.sender` must be either the `from` account or an operator for `from`.

Returns the encrypted amount that was actually transferred._

### confidentialTransferFrom

```solidity
function confidentialTransferFrom(address from, address to, euint64 amount) external returns (euint64 transferred)
```

_Similar to {confidentialTransferFrom-address-einput-bytes} but without an input proof. The caller
*must* be already approved by ACL for the given `amount`._

### confidentialTransferAndCall

```solidity
function confidentialTransferAndCall(address to, einput encryptedAmount, bytes inputProof, bytes data) external returns (euint64 transferred)
```

_Similar to {confidentialTransfer-address-einput-bytes} but with a callback to `to` after the transfer.

The callback is made to the {IConfidentialFungibleTokenReceiver-onConfidentialTransferReceived} function on the
`to` address with the actual transferred amount (may differ from the given `encryptedAmount`) and the given
data `data`._

### confidentialTransferAndCall

```solidity
function confidentialTransferAndCall(address to, euint64 amount, bytes data) external returns (euint64 transferred)
```

_Similar to {confidentialTransfer-address-euint64} but with a callback to `to` after the transfer._

### confidentialTransferFromAndCall

```solidity
function confidentialTransferFromAndCall(address from, address to, einput encryptedAmount, bytes inputProof, bytes data) external returns (euint64 transferred)
```

_Similar to {confidentialTransferFrom-address-einput-bytes} but with a callback to `to` after the transfer._

### confidentialTransferFromAndCall

```solidity
function confidentialTransferFromAndCall(address from, address to, euint64 amount, bytes data) external returns (euint64 transferred)
```

_Similar to {confidentialTransferFrom-address-euint64} but with a callback to `to` after the transfer._

## IConfidentialFungibleTokenReceiver

_Interface for contracts that can receive confidential token transfers with a callback._

### onConfidentialTransferReceived

```solidity
function onConfidentialTransferReceived(address operator, address from, euint64 amount, bytes data) external returns (ebool)
```

_Called upon receiving a confidential token transfer. Returns an encrypted boolean indicating success
of the callback. If false is returned, the transfer must be reversed._

## ConfidentialPair

_A simple confidential swap contract for swapping between ConfidentialFungibleTokens. This contract is unaudited and written
solely for educational purposes._

### Swap0to1

```solidity
event Swap0to1(address caller, euint64 amountIn, euint64 amountOut)
```

_Event emitted when a user `caller` swaps `amountIn` of `token0` for `amountOut` of `token1`._

### RateExposed

```solidity
event RateExposed(uint64 rate)
```

_Event emitted when the current rate for swapping `token0` for `token1` is exposed.
Rate is expressed as 1000x the ratio of the reserves of `token0` and `token1`._

### UnauthorizedUseOfEncryptedValue

```solidity
error UnauthorizedUseOfEncryptedValue(euint64 amount, address user)
```

### ConfidentialPairrUnauthorizedCaller

```solidity
error ConfidentialPairrUnauthorizedCaller(address caller)
```

### constructor

```solidity
constructor(address token0, address token1) public
```

### swap0to1

```solidity
function swap0to1(euint64 amountIn, euint64 amountOut) public returns (ebool)
```

_Function to swap from `token0` to `token1`. Function will revert if the contract is not approved as an
operator for the caller on `token0. User must be allowed to read encrypted values._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountIn | euint64 | The amount of `token0` to be transferred from the caller to this contract. |
| amountOut | euint64 | The amount of `token1` to be transferred from the contract to the user. This must be valid in the swap function: `x * y = k` where `k` is strictly increasing and `x` is the `token0` reserve and `y` is the `token1` reserve. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | ebool | success True if the swap results in a non-zero transfer to the user. False if the swap is for 0 or fails for any reason. |

### swap0to1

```solidity
function swap0to1(einput amountIn, einput amountOut, bytes inAmountProof, bytes outAmountProof) public returns (ebool)
```

_Alternative version of the swap function that gives users read access to encrypted parameters._

### exposeRate

```solidity
function exposeRate(uint256, uint64 reserves0, uint64 reserves1) external
```

### _requestExposeRate

```solidity
function _requestExposeRate() external
```

## ERC20ConfidentialPair

### constructor

```solidity
constructor(address token0, address token1) public
```

### requestSwap0to1

```solidity
function requestSwap0to1(uint64 amountIn, euint64 amountOut) public
```

## tryIncrease

```solidity
function tryIncrease(euint64 oldValue, euint64 delta) internal returns (ebool success, euint64 updated)
```

## tryDecrease

```solidity
function tryDecrease(euint64 oldValue, euint64 delta) internal returns (ebool success, euint64 updated)
```

## ConfidentialFungibleToken

_Reference implementation for {IConfidentialFungibleToken}.

This contract implements a fungible token where balances and transfers are encrypted using the Zama fhEVM,
providing confidentiality to users. Token amounts are stored as encrypted, unsigned integers (euint64)
that can only be decrypted by authorized parties.

Key features:

- All balances are encrypted
- Transfers happen without revealing amounts
- Support for operators (delegated transfer capabilities with time bounds)
- ERC1363-like functionality with transfer-and-call pattern
- Safe overflow/underflow handling for FHE operations_

### ConfidentialFungibleTokenInvalidReceiver

```solidity
error ConfidentialFungibleTokenInvalidReceiver(address receiver)
```

_The given receiver `receiver` is invalid for transfers._

### ConfidentialFungibleTokenInvalidSender

```solidity
error ConfidentialFungibleTokenInvalidSender(address sender)
```

_The given sender `sender` is invalid for transfers._

### ConfidentialFungibleTokenUnauthorizedSpender

```solidity
error ConfidentialFungibleTokenUnauthorizedSpender(address holder, address spender)
```

_The given holder `holder` is not authorized to spend on behalf of `spender`._

### ConfidentialFungibleTokenZeroBalance

```solidity
error ConfidentialFungibleTokenZeroBalance(address holder)
```

_The `holder` is trying to send tokens but has a balance of 0._

### ConfidentialFungibleTokenUnauthorizedUseOfEncryptedValue

```solidity
error ConfidentialFungibleTokenUnauthorizedUseOfEncryptedValue(euint64 amount, address user)
```

_The caller `user` does not have access to the encrypted value `amount`.

NOTE: Try using the equivalent transfer function with an input proof._

### ConfidentialFungibleTokenUnauthorizedCaller

```solidity
error ConfidentialFungibleTokenUnauthorizedCaller(address caller)
```

### ConfidentialFungibleTokenInvalidGatewayRequest

```solidity
error ConfidentialFungibleTokenInvalidGatewayRequest(uint256 requestId)
```

### onlyGateway

```solidity
modifier onlyGateway()
```

### constructor

```solidity
constructor(string name_, string symbol_, string tokenURI_) internal
```

### name

```solidity
function name() public view virtual returns (string)
```

_Returns the name of the token._

### symbol

```solidity
function symbol() public view virtual returns (string)
```

_Returns the symbol of the token._

### decimals

```solidity
function decimals() public view virtual returns (uint8)
```

_Returns the number of decimals of the token. Recommended to be 9._

### tokenURI

```solidity
function tokenURI() public view virtual returns (string)
```

_Returns the token URI._

### totalSupply

```solidity
function totalSupply() public view virtual returns (euint64)
```

_Returns the encrypted total supply of the token._

### balanceOf

```solidity
function balanceOf(address account) public view virtual returns (euint64)
```

_Returns the encrypted balance of the account `account`._

### isOperator

```solidity
function isOperator(address holder, address spender) public view virtual returns (bool)
```

_Returns true if `spender` is currently an operator for `holder`._

### setOperator

```solidity
function setOperator(address operator, uint48 until) public virtual
```

_Sets `operator` as an operator for `holder` until the timestamp `until`.

NOTE: An operator may transfer any amount of tokens on behalf of a holder while approved._

### confidentialTransfer

```solidity
function confidentialTransfer(address to, einput encryptedAmount, bytes inputProof) public virtual returns (euint64 transferred)
```

_Transfers the encrypted amount `encryptedAmount` to `to` with the given input proof `inputProof`.

Returns the encrypted amount that was actually transferred._

### confidentialTransfer

```solidity
function confidentialTransfer(address to, euint64 amount) public virtual returns (euint64 transferred)
```

_Similar to {confidentialTransfer-address-einput-bytes} but without an input proof. The caller
*must* already be approved by ACL for the given `amount`._

### confidentialTransferFrom

```solidity
function confidentialTransferFrom(address from, address to, einput encryptedAmount, bytes inputProof) public virtual returns (euint64 transferred)
```

_Transfers the encrypted amount `encryptedAmount` from `from` to `to` with the given input proof
`inputProof`. `msg.sender` must be either the `from` account or an operator for `from`.

Returns the encrypted amount that was actually transferred._

### confidentialTransferFrom

```solidity
function confidentialTransferFrom(address from, address to, euint64 amount) public virtual returns (euint64 transferred)
```

_Similar to {confidentialTransferFrom-address-einput-bytes} but without an input proof. The caller
*must* be already approved by ACL for the given `amount`._

### confidentialTransferAndCall

```solidity
function confidentialTransferAndCall(address to, einput encryptedAmount, bytes inputProof, bytes data) public virtual returns (euint64 transferred)
```

_Similar to {confidentialTransfer-address-einput-bytes} but with a callback to `to` after the transfer.

The callback is made to the {IConfidentialFungibleTokenReceiver-onConfidentialTransferReceived} function on the
`to` address with the actual transferred amount (may differ from the given `encryptedAmount`) and the given
data `data`._

### confidentialTransferAndCall

```solidity
function confidentialTransferAndCall(address to, euint64 amount, bytes data) public virtual returns (euint64 transferred)
```

_Similar to {confidentialTransfer-address-euint64} but with a callback to `to` after the transfer._

### confidentialTransferFromAndCall

```solidity
function confidentialTransferFromAndCall(address from, address to, einput encryptedAmount, bytes inputProof, bytes data) public virtual returns (euint64 transferred)
```

_Similar to {confidentialTransferFrom-address-einput-bytes} but with a callback to `to` after the transfer._

### confidentialTransferFromAndCall

```solidity
function confidentialTransferFromAndCall(address from, address to, euint64 amount, bytes data) public virtual returns (euint64 transferred)
```

_Similar to {confidentialTransferFrom-address-euint64} but with a callback to `to` after the transfer._

### discloseEncryptedAmount

```solidity
function discloseEncryptedAmount(euint64 encryptedAmount) public virtual
```

### finalizeDiscloseEncryptedAmount

```solidity
function finalizeDiscloseEncryptedAmount(uint256 requestId, uint64 amount) public virtual
```

### _setOperator

```solidity
function _setOperator(address holder, address operator, uint48 until) internal virtual
```

### _mint

```solidity
function _mint(address to, euint64 amount) internal returns (euint64 transferred)
```

### _burn

```solidity
function _burn(address from, euint64 amount) internal returns (euint64 transferred)
```

### _transfer

```solidity
function _transfer(address from, address to, euint64 amount) internal returns (euint64 transferred)
```

### _transferAndCall

```solidity
function _transferAndCall(address from, address to, euint64 amount, bytes data) internal returns (euint64 transferred)
```

### _update

```solidity
function _update(address from, address to, euint64 amount) internal virtual returns (euint64 transferred)
```

## ConfidentialFungibleTokenUtils

_Library that provides common {ConfidentialFungibleToken} utility functions._

### checkOnERC1363TransferReceived

```solidity
function checkOnERC1363TransferReceived(address operator, address from, address to, euint64 value, bytes data) internal returns (ebool)
```

_Performs an `ERC1363` like transfer callback to the recipient of the transfer `to`. Should be invoked
after all transfers "withCallback" on a {ConfidentialFungibleToken}.

The transfer callback is not invoked on the recipient if the recipient has no code (i.e. is an EOA). If the
recipient has non-zero code, it must implement
{IConfidentialFungibleTokenReceiver-onConfidentialTransferReceived} and return an `ebool` indicating
whether the transfer was accepted or not. If the `ebool` is `false`, the transfer will be reversed._

## MyConfidentialERC20

This contract implements an encrypted ERC20-like token with confidential balances using Zama's FHE library.

_It supports typical ERC20 functionality such as transferring tokens, minting, and setting allowances,
but uses encrypted data types._

### constructor

```solidity
constructor(string name_, string symbol_) public
```

Constructor to initialize the token's name and symbol, and set up the owner

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| name_ | string | The name of the token |
| symbol_ | string | The symbol of the token |

## TestAsyncDecrypt

Contract for testing asynchronous decryption using the Gateway

### xBool

```solidity
ebool xBool
```

_Encrypted state variables_

### xUint4

```solidity
euint4 xUint4
```

### xUint8

```solidity
euint8 xUint8
```

### xUint16

```solidity
euint16 xUint16
```

### xUint32

```solidity
euint32 xUint32
```

### xUint64

```solidity
euint64 xUint64
```

### xUint64_2

```solidity
euint64 xUint64_2
```

### xUint64_3

```solidity
euint64 xUint64_3
```

### xUint128

```solidity
euint128 xUint128
```

### xAddress

```solidity
eaddress xAddress
```

### xAddress2

```solidity
eaddress xAddress2
```

### xUint256

```solidity
euint256 xUint256
```

### yBool

```solidity
bool yBool
```

_Decrypted state variables_

### yUint4

```solidity
uint8 yUint4
```

### yUint8

```solidity
uint8 yUint8
```

### yUint16

```solidity
uint16 yUint16
```

### yUint32

```solidity
uint32 yUint32
```

### yUint64

```solidity
uint64 yUint64
```

### yUint64_2

```solidity
uint64 yUint64_2
```

### yUint64_3

```solidity
uint64 yUint64_3
```

### yUint128

```solidity
uint128 yUint128
```

### yAddress

```solidity
address yAddress
```

### yAddress2

```solidity
address yAddress2
```

### yUint256

```solidity
uint256 yUint256
```

### yBytes64

```solidity
bytes yBytes64
```

### yBytes128

```solidity
bytes yBytes128
```

### yBytes256

```solidity
bytes yBytes256
```

### latestRequestID

```solidity
uint256 latestRequestID
```

_Tracks the latest decryption request ID_

### constructor

```solidity
constructor() public
```

Constructor to initialize the contract and set up encrypted values

### requestBoolAboveDelay

```solidity
function requestBoolAboveDelay() public
```

Function to request decryption with an excessive delay (should revert)

### requestBool

```solidity
function requestBool() public
```

Request decryption of a boolean value

### requestBoolTrustless

```solidity
function requestBoolTrustless() public
```

Request decryption of a boolean value in trustless mode

### callbackBool

```solidity
function callbackBool(uint256, bool decryptedInput) public returns (bool)
```

Callback function for non-trustless boolean decryption

### callbackBoolTrustless

```solidity
function callbackBoolTrustless(uint256 requestID, bool decryptedInput, bytes[] signatures) public returns (bool)
```

Callback function for trustless boolean decryption

### requestUint4

```solidity
function requestUint4() public
```

Request decryption of a 4-bit unsigned integer

### callbackUint4

```solidity
function callbackUint4(uint256, uint8 decryptedInput) public returns (uint8)
```

Callback function for 4-bit unsigned integer decryption

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
|  | uint256 |  |
| decryptedInput | uint8 | The decrypted 4-bit unsigned integer |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint8 | The decrypted value |

### requestUint8

```solidity
function requestUint8() public
```

Request decryption of an 8-bit unsigned integer

### callbackUint8

```solidity
function callbackUint8(uint256, uint8 decryptedInput) public returns (uint8)
```

Callback function for 8-bit unsigned integer decryption

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
|  | uint256 |  |
| decryptedInput | uint8 | The decrypted 8-bit unsigned integer |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint8 | The decrypted value |

### requestUint16

```solidity
function requestUint16() public
```

Request decryption of a 16-bit unsigned integer

### callbackUint16

```solidity
function callbackUint16(uint256, uint16 decryptedInput) public returns (uint16)
```

Callback function for 16-bit unsigned integer decryption

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
|  | uint256 |  |
| decryptedInput | uint16 | The decrypted 16-bit unsigned integer |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint16 | The decrypted value |

### requestUint32

```solidity
function requestUint32(uint32 input1, uint32 input2) public
```

Request decryption of a 32-bit unsigned integer with additional inputs

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| input1 | uint32 | First additional input |
| input2 | uint32 | Second additional input |

### callbackUint32

```solidity
function callbackUint32(uint256 requestID, uint32 decryptedInput) public returns (uint32)
```

Callback function for 32-bit unsigned integer decryption

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| requestID | uint256 | The ID of the decryption request |
| decryptedInput | uint32 | The decrypted 32-bit unsigned integer |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint32 | The result of the computation |

### requestUint64

```solidity
function requestUint64() public
```

Request decryption of a 64-bit unsigned integer

### requestUint64NonTrivial

```solidity
function requestUint64NonTrivial(einput inputHandle, bytes inputProof) public
```

Request decryption of a non-trivial 64-bit unsigned integer

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| inputHandle | einput | The input handle for the encrypted value |
| inputProof | bytes | The input proof for the encrypted value |

### callbackUint64

```solidity
function callbackUint64(uint256, uint64 decryptedInput) public returns (uint64)
```

Callback function for 64-bit unsigned integer decryption

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
|  | uint256 |  |
| decryptedInput | uint64 | The decrypted 64-bit unsigned integer |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint64 | The decrypted value |

### requestUint128

```solidity
function requestUint128() public
```

### requestUint128NonTrivial

```solidity
function requestUint128NonTrivial(einput inputHandle, bytes inputProof) public
```

### callbackUint128

```solidity
function callbackUint128(uint256, uint128 decryptedInput) public returns (uint128)
```

### requestUint256

```solidity
function requestUint256() public
```

### requestUint256NonTrivial

```solidity
function requestUint256NonTrivial(einput inputHandle, bytes inputProof) public
```

### callbackUint256

```solidity
function callbackUint256(uint256, uint256 decryptedInput) public returns (uint256)
```

### requestEbytes64NonTrivial

```solidity
function requestEbytes64NonTrivial(einput inputHandle, bytes inputProof) public
```

### requestEbytes64Trivial

```solidity
function requestEbytes64Trivial(bytes value) public
```

### callbackBytes64

```solidity
function callbackBytes64(uint256, bytes decryptedInput) public returns (bytes)
```

### requestEbytes128NonTrivial

```solidity
function requestEbytes128NonTrivial(einput inputHandle, bytes inputProof) public
```

### requestEbytes128Trivial

```solidity
function requestEbytes128Trivial(bytes value) public
```

### callbackBytes128

```solidity
function callbackBytes128(uint256, bytes decryptedInput) public returns (bytes)
```

### requestEbytes256Trivial

```solidity
function requestEbytes256Trivial(bytes value) public
```

### requestEbytes256NonTrivial

```solidity
function requestEbytes256NonTrivial(einput inputHandle, bytes inputProof) public
```

### callbackBytes256

```solidity
function callbackBytes256(uint256, bytes decryptedInput) public returns (bytes)
```

Callback function for 256-bit encrypted bytes decryption

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
|  | uint256 |  |
| decryptedInput | bytes | The decrypted 256-bit bytes |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bytes | The decrypted value |

### requestAddress

```solidity
function requestAddress() public
```

Request decryption of an encrypted address

### requestSeveralAddresses

```solidity
function requestSeveralAddresses() public
```

Request decryption of multiple encrypted addresses

### callbackAddresses

```solidity
function callbackAddresses(uint256, address decryptedInput1, address decryptedInput2) public returns (address)
```

Callback function for multiple address decryption

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
|  | uint256 |  |
| decryptedInput1 | address | The first decrypted address |
| decryptedInput2 | address | The second decrypted address |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | address | The first decrypted address |

### callbackAddress

```solidity
function callbackAddress(uint256, address decryptedInput) public returns (address)
```

Callback function for address decryption

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
|  | uint256 |  |
| decryptedInput | address | The decrypted address |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | address | The decrypted address |

### requestMixed

```solidity
function requestMixed(uint32 input1, uint32 input2) public
```

Request decryption of multiple encrypted data types

_This function demonstrates how to request decryption for various encrypted data types in a single call_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| input1 | uint32 | First additional input parameter for the callback function |
| input2 | uint32 | Second additional input parameter for the callback function |

### callbackMixed

```solidity
function callbackMixed(uint256 requestID, bool decBool_1, bool decBool_2, uint8 decUint4, uint8 decUint8, uint16 decUint16, uint32 decUint32, uint64 decUint64_1, uint64 decUint64_2, uint64 decUint64_3, address decAddress) public returns (uint8)
```

Callback function for mixed data type decryption

_Processes the decrypted values and performs some basic checks_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| requestID | uint256 | The ID of the decryption request |
| decBool_1 | bool | First decrypted boolean |
| decBool_2 | bool | Second decrypted boolean |
| decUint4 | uint8 | Decrypted 4-bit unsigned integer |
| decUint8 | uint8 | Decrypted 8-bit unsigned integer |
| decUint16 | uint16 | Decrypted 16-bit unsigned integer |
| decUint32 | uint32 | Decrypted 32-bit unsigned integer |
| decUint64_1 | uint64 | First decrypted 64-bit unsigned integer |
| decUint64_2 | uint64 | Second decrypted 64-bit unsigned integer |
| decUint64_3 | uint64 | Third decrypted 64-bit unsigned integer |
| decAddress | address | Decrypted address |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint8 | The decrypted 4-bit unsigned integer |

### requestMixedBytes256

```solidity
function requestMixedBytes256(einput inputHandle, bytes inputProof) public
```

Request decryption of mixed data types including 256-bit encrypted bytes

_Demonstrates how to include encrypted bytes256 in a mixed decryption request_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| inputHandle | einput | The encrypted input handle for the bytes256 |
| inputProof | bytes | The proof for the encrypted bytes256 |

### callbackMixedBytes256

```solidity
function callbackMixedBytes256(uint256, bool decBool, address decAddress, bytes bytesRes, bytes bytesRes2) public
```

Callback function for mixed data type decryption including 256-bit encrypted bytes

_Processes and stores the decrypted values_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
|  | uint256 |  |
| decBool | bool | Decrypted boolean |
| decAddress | address | Decrypted address |
| bytesRes | bytes | Decrypted 256-bit bytes |
| bytesRes2 | bytes |  |

### requestEbytes256NonTrivialTrustless

```solidity
function requestEbytes256NonTrivialTrustless(einput inputHandle, bytes inputProof) public
```

Request trustless decryption of non-trivial 256-bit encrypted bytes

_Demonstrates how to request trustless decryption for complex encrypted bytes256_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| inputHandle | einput | The encrypted input handle for the bytes256 |
| inputProof | bytes | The proof for the encrypted bytes256 |

### callbackBytes256Trustless

```solidity
function callbackBytes256Trustless(uint256 requestID, bytes decryptedInput, bytes[] signatures) public returns (bytes)
```

Callback function for trustless decryption of 256-bit encrypted bytes

_Verifies the decryption result using KMS signatures_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| requestID | uint256 | The ID of the decryption request |
| decryptedInput | bytes | The decrypted bytes256 value |
| signatures | bytes[] | The signatures from the KMS for verification |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bytes | The decrypted bytes256 value |

### requestMixedBytes256Trustless

```solidity
function requestMixedBytes256Trustless(einput inputHandle, bytes inputProof) public
```

Request trustless decryption of mixed data types including 256-bit encrypted bytes

_Demonstrates how to request trustless decryption for multiple data types_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| inputHandle | einput | The encrypted input handle for the bytes256 |
| inputProof | bytes | The proof for the encrypted bytes256 |

### callbackMixedBytes256Trustless

```solidity
function callbackMixedBytes256Trustless(uint256 requestID, bool decBool, bytes bytesRes, address decAddress, bytes[] signatures) public
```

Callback function for trustless decryption of mixed data types including 256-bit encrypted bytes

_Verifies and processes the decrypted values_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| requestID | uint256 | The ID of the decryption request |
| decBool | bool | Decrypted boolean |
| bytesRes | bytes | Decrypted 256-bit bytes |
| decAddress | address | Decrypted address |
| signatures | bytes[] | The signatures from the KMS for verification |

## ConfidentialFungibleTokenERC20WrapperMock

### constructor

```solidity
constructor(contract IERC20 token, string name, string symbol, string uri) public
```

## ConfidentialFungibleTokenMock

### constructor

```solidity
constructor(string name_, string symbol_, string tokenURI_) public
```

### _update

```solidity
function _update(address from, address to, euint64 amount) internal virtual returns (euint64 transferred)
```

### $_mint

```solidity
function $_mint(address to, einput encryptedAmount, bytes inputProof) public returns (euint64 transferred)
```

### $_transfer

```solidity
function $_transfer(address from, address to, einput encryptedAmount, bytes inputProof) public returns (euint64 transferred)
```

### $_transferAndCall

```solidity
function $_transferAndCall(address from, address to, einput encryptedAmount, bytes inputProof, bytes data) public returns (euint64 transferred)
```

### $_burn

```solidity
function $_burn(address from, einput encryptedAmount, bytes inputProof) public returns (euint64 transferred)
```

### $_update

```solidity
function $_update(address from, address to, einput encryptedAmount, bytes inputProof) public virtual returns (euint64 transferred)
```

## ConfidentialFungibleTokenReceiverMock

### ConfidentialTransferCallback

```solidity
event ConfidentialTransferCallback(bool success)
```

### InvalidInput

```solidity
error InvalidInput(uint8 input)
```

### onConfidentialTransferReceived

```solidity
function onConfidentialTransferReceived(address, address, euint64, bytes data) external returns (ebool)
```

Data should contain a success boolean (plaintext). Revert if not.

## ERC20Mock

### constructor

```solidity
constructor(string name_, string symbol_, uint8 decimals_) public
```

### decimals

```solidity
function decimals() public view virtual returns (uint8)
```

_Returns the number of decimals used to get its user representation.
For example, if `decimals` equals `2`, a balance of `505` tokens should
be displayed to a user as `5.05` (`505 / 10 ** 2`).

Tokens usually opt for a value of 18, imitating the relationship between
Ether and Wei. This is the default value returned by this function, unless
it's overridden.

NOTE: This information is only used for _display_ purposes: it in
no way affects any of the arithmetic of the contract, including
{IERC20-balanceOf} and {IERC20-transfer}._

## ERC20RevertDecimalsMock

### constructor

```solidity
constructor() public
```

### decimals

```solidity
function decimals() public pure returns (uint8)
```

_Returns the number of decimals used to get its user representation.
For example, if `decimals` equals `2`, a balance of `505` tokens should
be displayed to a user as `5.05` (`505 / 10 ** 2`).

Tokens usually opt for a value of 18, imitating the relationship between
Ether and Wei. This is the default value returned by this function, unless
it's overridden.

NOTE: This information is only used for _display_ purposes: it in
no way affects any of the arithmetic of the contract, including
{IERC20-balanceOf} and {IERC20-transfer}._

## ERC20ExcessDecimalsMock

### constructor

```solidity
constructor() public
```

### decimals

```solidity
function decimals() public pure returns (uint8)
```

_Returns the number of decimals used to get its user representation.
For example, if `decimals` equals `2`, a balance of `505` tokens should
be displayed to a user as `5.05` (`505 / 10 ** 2`).

Tokens usually opt for a value of 18, imitating the relationship between
Ether and Wei. This is the default value returned by this function, unless
it's overridden.

NOTE: This information is only used for _display_ purposes: it in
no way affects any of the arithmetic of the contract, including
{IERC20-balanceOf} and {IERC20-transfer}._

## ConfidentialPair

_A simple confidential swap contract for swapping between ConfidentialFungibleTokens. This contract is unaudited and written
solely for educational purposes._

### Swap0to1

```solidity
event Swap0to1(address caller, euint64 amountIn, euint64 amountOut)
```

_Event emitted when a user `caller` swaps `amountIn` of `token0` for `amountOut` of `token1`._

### RateExposed

```solidity
event RateExposed(uint64 rate)
```

_Event emitted when the current rate for swapping `token0` for `token1` is exposed.
Rate is expressed as 1000x the ratio of the reserves of `token0` and `token1`._

### UnauthorizedUseOfEncryptedValue

```solidity
error UnauthorizedUseOfEncryptedValue(euint64 amount, address user)
```

### ConfidentialPairrUnauthorizedCaller

```solidity
error ConfidentialPairrUnauthorizedCaller(address caller)
```

### constructor

```solidity
constructor(address token0, address token1) public
```

### swap0to1

```solidity
function swap0to1(euint64 amountIn, euint64 amountOut) public returns (ebool)
```

_Function to swap from `token0` to `token1`. Function will revert if the contract is not approved as an
operator for the caller on `token0. User must be allowed to read encrypted values._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountIn | euint64 | The amount of `token0` to be transferred from the caller to this contract. |
| amountOut | euint64 | The amount of `token1` to be transferred from the contract to the user. This must be valid in the swap function: `x * y = k` where `k` is strictly increasing and `x` is the `token0` reserve and `y` is the `token1` reserve. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | ebool | success True if the swap results in a non-zero transfer to the user. False if the swap is for 0 or fails for any reason. |

### swap0to1

```solidity
function swap0to1(einput amountIn, einput amountOut, bytes inAmountProof, bytes outAmountProof) public returns (ebool)
```

_Alternative version of the swap function that gives users read access to encrypted parameters._

### exposeRate

```solidity
function exposeRate(uint256, uint64 reserves0, uint64 reserves1) external
```

### _requestExposeRate

```solidity
function _requestExposeRate() external
```

## ERC20ConfidentialPair

### constructor

```solidity
constructor(address token0, address token1) public
```

### requestSwap0to1

```solidity
function requestSwap0to1(uint64 amountIn, euint64 amountOut) public
```

## ConfidentialFungibleTokenERC20Wrapper

_A wrapper contract built on top of {ConfidentialFungibleToken} that allows wrapping an `ERC20` token
into a confidential fungible token. The wrapper contract implements the {IERC1363Receiver} interface
which allows users to transfer `ERC1363` tokens directly to the wrapper with a callback to wrap the tokens._

### constructor

```solidity
constructor(contract IERC20 underlying_) internal
```

### decimals

```solidity
function decimals() public view virtual returns (uint8)
```

_Returns the number of decimals of the token. Recommended to be 9._

### rate

```solidity
function rate() public view virtual returns (uint256)
```

_Returns the rate at which the underlying token is converted to the wrapped token.
For example, if the `rate` is 1000, then 1000 units of the underlying token equal 1 unit of the wrapped token._

### underlying

```solidity
function underlying() public view returns (contract IERC20)
```

_Returns the address of the underlying ERC-20 token that is being wrapped._

### onTransferReceived

```solidity
function onTransferReceived(address, address from, uint256 value, bytes data) public virtual returns (bytes4)
```

_`ERC1363` callback function which wraps tokens to the address specified in `data` or
the address `from` (if no address is specified in `data`). This function refunds any excess tokens
sent beyond the nearest multiple of {rate}. See {wrap} from more details on wrapping tokens._

### wrap

```solidity
function wrap(address to, uint256 value) public virtual
```

_Wraps value `value` of the underlying token into a confidential token and sends it to
`to`. Tokens are exchanged at a fixed rate specified by {rate} such that `value / rate()` confidential
tokens are sent. Amount transferred in is rounded down to the nearest multiple of {rate}._

### unwrap

```solidity
function unwrap(address from, address to, euint64 amount) public virtual
```

_Unwraps tokens from `from` and sends the underlying tokens to `to`. The caller must be `from`
or be an approved operator for `from`. `amount * rate()` underlying tokens are sent to `to`.

NOTE: This is an asynchronous function and waits for decryption to be completed off-chain before disbursing
tokens.
NOTE: The caller *must* already be approved by ACL for the given `amount`._

### unwrap

```solidity
function unwrap(address from, address to, einput encryptedAmount, bytes inputProof) public virtual
```

_Variant of {unwrap} that passes an `inputProof` which approves the caller for the `encryptedAmount`
in the ACL._

### _unwrap

```solidity
function _unwrap(address from, address to, euint64 amount) internal virtual
```

### finalizeUnwrap

```solidity
function finalizeUnwrap(uint256 requestID, uint64 amount) public virtual
```

_Called by the fhEVM gateway with the decrypted amount `amount` for a request id `requestId`.
Fills unwrap requests._

