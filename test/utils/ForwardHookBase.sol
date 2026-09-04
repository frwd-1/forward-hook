// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {ForwardHook} from "../../src/ForwardHook.sol";

/// @dev shared wiring for every ForwardHook suite
abstract contract ForwardHookBase is Test, Deployers {
    /// @dev keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)")
    bytes32 internal constant SWAP_TOPIC = 0x40e9cecb9f5f1f1c5b9c97dec2917b7ee92e57ba5563708daca94dd84ad7112f;

    uint24 internal constant DEFAULT_FEE = 3000;
    int24 internal constant TICK_SPACING = 60;

    ForwardHook internal hook;

    address internal underwriter = makeAddr("underwriter");
    address internal admin = address(this);

    function hookFlags() internal pure returns (uint160) {
        return uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG);
    }

    /// @dev arbitrary base address carrying the permission bits the PoolManager checks
    function hookAddress() internal pure returns (address) {
        return address(hookFlags() | uint160(0x4444 << 20));
    }

    function deployHook() internal returns (ForwardHook) {
        address target = hookAddress();
        deployCodeTo("ForwardHook.sol:ForwardHook", abi.encode(manager, admin, underwriter, DEFAULT_FEE), target);
        return ForwardHook(target);
    }

    /// @dev swaps currency0 for currency1 and returns the fee the pool reported
    function swapAndReadFee(PoolSwapTest router, uint256 amountIn, uint256 value) internal returns (uint24 fee) {
        vm.recordLogs();

        router.swap{value: value}(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(amountIn),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ZERO_BYTES
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(manager) && logs[i].topics[0] == SWAP_TOPIC) {
                (,,,,, fee) = abi.decode(logs[i].data, (int128, int128, uint160, uint128, int24, uint24));
                return fee;
            }
        }
        revert("no swap event");
    }
}
