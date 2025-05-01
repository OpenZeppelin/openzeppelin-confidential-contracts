// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract VestingBase {
    struct VestingStream {
        uint48 startTime;
        address recipient;
        uint256 totalAmount;
        uint256 amountPerSecond;
        uint256 claimed;
    }

    mapping(uint256 => VestingStream) private _vestingStreams;
    uint256 numVestingStreams;

    function _doTransferIn(address from, uint256 amount) internal virtual returns (uint256);

    function _doTransferOut(address to, uint256 amount) internal virtual returns (uint256);

    function _mul(uint256 a, uint256 b) internal virtual returns (uint256);

    function _sub(uint256 a, uint256 b) internal virtual returns (uint256);

    function _add(uint256 a, uint256 b) internal virtual returns (uint256);

    function _min(uint256 a, uint256 b) internal virtual returns (uint256);

    function _prestore(uint256 a) internal virtual returns (uint256) {}

    function _createVestingStream(
        uint48 startTime,
        address recipient,
        uint256 amount,
        uint256 amountPerSecond
    ) internal {
        uint256 amountTransferredIn = _doTransferIn(msg.sender, amount);

        _vestingStreams[++numVestingStreams] = VestingStream({
            startTime: startTime,
            recipient: recipient,
            totalAmount: _prestore(_min(amountTransferredIn, amount)),
            amountPerSecond: _prestore(amountPerSecond),
            claimed: 0
        });
    }

    function claim(uint256 streamId) public virtual {
        require(msg.sender == _vestingStreams[streamId].recipient);
        _claim(streamId);
    }

    function _claim(uint256 streamId) internal virtual {
        VestingStream storage stream = _vestingStreams[streamId];
        uint256 claimAmount = _sub(
            _min(_mul(block.timestamp - stream.startTime, stream.amountPerSecond), stream.totalAmount),
            stream.claimed
        );

        uint256 amountTransferredOut = _doTransferOut(stream.recipient, claimAmount);
        stream.claimed = _prestore(_add(stream.claimed, amountTransferredOut));
    }
}
