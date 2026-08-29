// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
// import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
// import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
// import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
// import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

// contract PoolStateReader is BaseHook {
//     using PoolIdLibrary for PoolKey;
//     using StateLibrary for IPoolManager;

//     constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
//         poolManager = _poolManager;
//     }
// }
