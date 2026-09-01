// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @dev Enumerable address set for invariant-test actor management.
/// Classic Foundry invariant-testing helper (add / contains / count / rand / forEach /
/// reduce). Lets a handler track the set of actors it has used so invariants can sum
/// state across exactly the addresses the fuzzer touched.
struct AddressSet {
    address[] addrs;
    mapping(address => bool) saved;
}

library LibAddressSet {
    function add(AddressSet storage s, address addr) internal {
        if (!s.saved[addr]) {
            s.addrs.push(addr);
            s.saved[addr] = true;
        }
    }

    function contains(AddressSet storage s, address addr) internal view returns (bool) {
        return s.saved[addr];
    }

    function count(AddressSet storage s) internal view returns (uint256) {
        return s.addrs.length;
    }

    /// @dev Deterministically pick an actor from the set by fuzzer-provided seed.
    /// Falls back to address(0) when the set is empty (callers should guard).
    function rand(AddressSet storage s, uint256 seed) internal view returns (address) {
        if (s.addrs.length == 0) return address(0);
        return s.addrs[seed % s.addrs.length];
    }

    function forEach(AddressSet storage s, function(address) external func) internal {
        for (uint256 i; i < s.addrs.length; ++i) {
            func(s.addrs[i]);
        }
    }

    function reduce(
        AddressSet storage s,
        uint256 acc,
        function(uint256, address) external returns (uint256) func
    ) internal returns (uint256) {
        for (uint256 i; i < s.addrs.length; ++i) {
            acc = func(acc, s.addrs[i]);
        }
        return acc;
    }
}
