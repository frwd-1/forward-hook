// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseDynamicFee} from "@openzeppelin/uniswap-hooks/src/fee/BaseDynamicFee.sol";

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {BaseOverrideFee} from "@openzeppelin/uniswap-hooks/src/fee/BaseOverrideFee.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {SubScript} from "./SubScript.sol";

// import {PoolStateReader} from "./PoolStateReader.sol";

/// @author frwd labs
/// @title SwiftHook
/// @notice This hook is used to manage the capabilities of the pool

contract SwiftHook is BaseOverrideFee, SubScript {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    constructor(
        IPoolManager _poolManager,
        address _underwriter
    ) BaseHook(_poolManager) SubScript(_underwriter) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    /// TODO: DOUBLE CHECK THIS
    function _getFee(
        /// TODO: NOT SURE I LIKE "AGENT" HERE
        address agent,
        PoolKey calldata,
        SwapParams calldata,
        bytes calldata
    ) internal view override returns (uint24) {
        bytes32 capability = assignments[agent];
        return capabilities[capability].fee;
    }
}
