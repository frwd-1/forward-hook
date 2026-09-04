// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {ForwardHookFixture} from "../utils/ForwardHookFixture.sol";

contract ForwardHookFeesTest is ForwardHookFixture {
    using StateLibrary for IPoolManager;

    function test_swapWithoutCapabilityUsesDefaultFee() public {
        assertEq(swapAndReadFee(swapRouter), DEFAULT_FEE);
    }

    function test_swapWithCapabilityUsesCapabilityFee() public {
        vm.startPrank(underwriter);
        hook.commitProgram(MARKET_MAKER_STRUCTURE, MARKET_MAKER_LOGIC, MARKET_MAKER_FEE);
        hook.assignCapability(MARKET_MAKER, address(agentRouter));
        vm.stopPrank();

        assertEq(swapAndReadFee(agentRouter), MARKET_MAKER_FEE);
        assertEq(swapAndReadFee(swapRouter), DEFAULT_FEE);
    }

    /// @dev a zero fee capability must not collapse into the default fee
    function test_zeroFeeCapabilityIsHonoured() public {
        vm.startPrank(underwriter);
        hook.commitProgram(MARKET_MAKER_STRUCTURE, MARKET_MAKER_LOGIC, 0);
        hook.assignCapability(MARKET_MAKER, address(agentRouter));
        vm.stopPrank();

        assertEq(swapAndReadFee(agentRouter), 0);
    }

    function testFuzz_setDefaultFee(uint24 fee) public {
        fee = uint24(bound(fee, 0, LPFeeLibrary.MAX_LP_FEE));

        vm.prank(underwriter);
        hook.setDefaultFee(key, fee);

        (,,, uint24 lpFee) = manager.getSlot0(key.toId());
        assertEq(lpFee, fee);
        assertEq(hook.defaultFee(), fee);
        assertEq(swapAndReadFee(swapRouter), fee);
    }

    function testFuzz_setDefaultFeeRejectsOversizedFee(uint24 fee) public {
        vm.assume(fee > LPFeeLibrary.MAX_LP_FEE);

        vm.prank(underwriter);
        vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, fee));
        hook.setDefaultFee(key, fee);
    }
}
