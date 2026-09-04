// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

import {ForwardHookBase} from "./ForwardHookBase.sol";

/// @dev local pool of two mock tokens with the hook attached
abstract contract ForwardHookFixture is ForwardHookBase {
    bytes32 internal constant MARKET_MAKER_STRUCTURE = keccak256("MARKET_MAKER_STRUCTURE");
    bytes32 internal constant MARKET_MAKER_LOGIC = keccak256("MARKET_MAKER_LOGIC");
    bytes32 internal constant MARKET_MAKER = keccak256(abi.encodePacked(MARKET_MAKER_STRUCTURE, MARKET_MAKER_LOGIC));
    uint24 internal constant MARKET_MAKER_FEE = 500;

    /// @dev stands in for an agent the underwriter can assign a capability to
    PoolSwapTest internal agentRouter;

    function setUp() public virtual {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        hook = deployHook();

        agentRouter = new PoolSwapTest(manager);
        approveCurrencies(address(agentRouter));

        (key,) = initPool(
            currency0,
            currency1,
            IHooks(address(hook)),
            LPFeeLibrary.DYNAMIC_FEE_FLAG,
            TICK_SPACING,
            Constants.SQRT_PRICE_1_1
        );

        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -600, tickUpper: 600, liquidityDelta: 100 ether, salt: bytes32(0)}),
            ZERO_BYTES
        );
    }

    function approveCurrencies(address spender) internal {
        MockERC20(Currency.unwrap(currency0)).approve(spender, type(uint256).max);
        MockERC20(Currency.unwrap(currency1)).approve(spender, type(uint256).max);
    }

    function swapAndReadFee(PoolSwapTest router) internal returns (uint24) {
        return swapAndReadFee(router, 0.01 ether, 0);
    }
}
