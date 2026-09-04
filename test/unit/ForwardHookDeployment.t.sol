// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {ForwardHook} from "../../src/ForwardHook.sol";
import {ForwardHookFixture} from "../utils/ForwardHookFixture.sol";

contract ForwardHookDeploymentTest is ForwardHookFixture {
    using StateLibrary for IPoolManager;

    function test_minedDeployment() public {
        bytes memory args = abi.encode(manager, admin, underwriter, DEFAULT_FEE);
        (address mined, bytes32 salt) = HookMiner.find(address(this), hookFlags(), type(ForwardHook).creationCode, args);

        ForwardHook deployed = new ForwardHook{salt: salt}(manager, admin, underwriter, DEFAULT_FEE);

        assertEq(address(deployed), mined);
        assertEq(address(deployed.poolManager()), address(manager));
    }

    function test_hookPermissions() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        assertTrue(permissions.afterInitialize);
        assertTrue(permissions.beforeSwap);
        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterSwap);
    }

    function test_constructorGrantsRoles() public view {
        assertTrue(hook.hasRole(hook.UNDERWRITER_ROLE(), underwriter));
        assertTrue(hook.hasRole(hook.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_initializeSeedsDefaultFee() public view {
        (,,, uint24 lpFee) = manager.getSlot0(key.toId());
        assertEq(lpFee, DEFAULT_FEE);
    }

    function test_initializeRejectsStaticFeePool() public {
        vm.expectRevert();
        initPool(currency0, currency1, IHooks(address(hook)), DEFAULT_FEE, TICK_SPACING, Constants.SQRT_PRICE_1_1);
    }
}
