// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BaseOverrideFee} from "@openzeppelin/uniswap-hooks/src/fee/BaseOverrideFee.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {SubScript} from "./SubScript.sol";

/// @author frwd labs
/// @title ForwardHook
/// @notice This hook is used to manage the capabilities of the pool

contract ForwardHook is BaseOverrideFee, SubScript {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    /// @dev admin is named rather than taken from msg.sender, which is the CREATE2 deployer
    error InvalidAdmin();

    constructor(
        IPoolManager _poolManager,
        address _admin,
        address _underwriter,
        uint24 _defaultFee
    ) BaseHook(_poolManager) SubScript(_underwriter, _defaultFee) {
        if (_admin == address(0)) revert InvalidAdmin();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /// @dev seeds the pool with the default fee once the dynamic fee check passes
    function _afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick
    ) internal override returns (bytes4) {
        bytes4 selector = super._afterInitialize(
            sender,
            key,
            sqrtPriceX96,
            tick
        );
        poolManager.updateDynamicLPFee(key, defaultFee);
        return selector;
    }

    function setDefaultFee(
        PoolKey calldata key,
        uint24 fee
    ) external onlyRole(UNDERWRITER_ROLE) {
        _setDefaultFee(fee);
        poolManager.updateDynamicLPFee(key, fee);
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
                afterInitialize: true,
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

    function _getFee(
        address agent,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    ) internal view override returns (uint24) {
        bytes32 capability = assignments[agent];

        if (!capabilities[capability].exists) {
            (, , , uint24 lpFee) = poolManager.getSlot0(key.toId());
            return lpFee;
        }

        return capabilities[capability].fee;
    }
}
