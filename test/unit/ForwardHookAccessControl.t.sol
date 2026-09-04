// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {ForwardHookFixture} from "../utils/ForwardHookFixture.sol";

contract ForwardHookAccessControlTest is ForwardHookFixture {
    address internal intruder = makeAddr("intruder");
    address internal lp = makeAddr("lp");

    function test_createCapabilityRequiresUnderwriter() public {
        vm.expectRevert(_unauthorized(intruder, hook.UNDERWRITER_ROLE()));
        vm.prank(intruder);
        hook.commitProgram(MARKET_MAKER_STRUCTURE, MARKET_MAKER_LOGIC, MARKET_MAKER_FEE);
    }

    function test_assignCapabilityRequiresUnderwriter() public {
        vm.expectRevert(_unauthorized(intruder, hook.UNDERWRITER_ROLE()));
        vm.prank(intruder);
        hook.assignCapability(MARKET_MAKER, address(agentRouter));
    }

    function test_setDefaultFeeRequiresUnderwriter() public {
        vm.expectRevert(_unauthorized(intruder, hook.UNDERWRITER_ROLE()));
        vm.prank(intruder);
        hook.setDefaultFee(key, 100);
    }

    function test_updateCapabilityFeeRequiresLp() public {
        vm.prank(underwriter);
        hook.commitProgram(MARKET_MAKER_STRUCTURE, MARKET_MAKER_LOGIC, MARKET_MAKER_FEE);

        vm.expectRevert(_unauthorized(underwriter, hook.LP_ROLE()));
        vm.prank(underwriter);
        hook.updateCapabilityFee(MARKET_MAKER, 100);
    }

    function test_lpCanUpdateCapabilityFee() public {
        hook.grantRole(hook.LP_ROLE(), lp);

        vm.startPrank(underwriter);
        hook.commitProgram(MARKET_MAKER_STRUCTURE, MARKET_MAKER_LOGIC, MARKET_MAKER_FEE);
        hook.assignCapability(MARKET_MAKER, address(agentRouter));
        vm.stopPrank();

        vm.prank(lp);
        hook.updateCapabilityFee(MARKET_MAKER, 100);

        assertEq(swapAndReadFee(agentRouter), 100);
    }

    function _unauthorized(address account, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, account, role);
    }
}
