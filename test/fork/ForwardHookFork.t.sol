// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/Test.sol";

import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";

import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {ForwardHookBase} from "../utils/ForwardHookBase.sol";

/// @dev runs against the live mainnet PoolManager, see .env.example for RPC setup
contract ForwardHookForkTest is ForwardHookBase {
    using StateLibrary for IPoolManager;

    IPoolManager internal constant MAINNET_POOL_MANAGER = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);

    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    /// @dev native ETH / LINK, 0.30%, no hooks
    PoolId internal constant REFERENCE_POOL_ID =
        PoolId.wrap(0xb2b5618903d74bbac9e9049a035c3827afc4487cde3b994a1568b050f4c8e2e4);
    uint24 internal constant REFERENCE_LP_FEE = 3000;

    /// @dev block of tx 0x2521bf732e6c502d3047bebda665b291b054d7d3e60eeacb90403a947cba7519
    uint256 internal constant REFERENCE_BLOCK = 25861513;
    /// @dev tick emitted by that transaction's Swap event
    int24 internal constant REFERENCE_BLOCK_TICK = 53673;

    /// @dev amounts emitted by that transaction's Swap event, the taker paid ETH for LINK
    uint256 internal constant REFERENCE_SWAP_ETH_IN = 140478187182262009856;
    uint256 internal constant REFERENCE_SWAP_LINK_OUT = 30017339414746898956127;

    /// @dev the fee the underwriter names for this searcher, a policy number
    uint24 internal constant SEARCHER_FEE = 10_000;

    /// @dev contract the searcher EOA called
    address internal constant MEV_BOT = 0xBdb3ba9ffe392549E1f8658DD2630c141fDF47B6;
    /// @dev address the PoolManager saw as the swap caller in that transaction
    address internal constant MEV_BOT_COUNTERPARTY = 0x9B7F4b2638006AdD6b50Db3a6C2618cEc571B703;

    bytes32 internal constant MEV_SEARCHER_STRUCTURE = keccak256("MEV_SEARCHER_STRUCTURE");
    bytes32 internal constant MEV_SEARCHER_LOGIC = keccak256("MEV_SEARCHER_LOGIC");
    bytes32 internal constant MEV_SEARCHER = keccak256(abi.encodePacked(MEV_SEARCHER_STRUCTURE, MEV_SEARCHER_LOGIC));

    PoolSwapTest internal mevRouter;

    function setUp() public {
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
            return;
        }

        uint256 forkBlock = vm.envOr("FORK_BLOCK", REFERENCE_BLOCK);
        if (forkBlock == 0) {
            vm.createSelectFork(rpcUrl);
        } else {
            vm.createSelectFork(rpcUrl, forkBlock);
        }

        manager = MAINNET_POOL_MANAGER;
        swapRouter = new PoolSwapTest(manager);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);

        // stand a router up at the address the hook will see as the swap caller
        deployCodeTo("PoolSwapTest.sol:PoolSwapTest", abi.encode(manager), MEV_BOT_COUNTERPARTY);
        mevRouter = PoolSwapTest(MEV_BOT_COUNTERPARTY);

        hook = deployHook();

        _mirrorReferencePool();
    }

    function test_fork_referencePoolIsVisible() public view {
        (uint160 sqrtPriceX96, int24 tick,, uint24 lpFee) = manager.getSlot0(REFERENCE_POOL_ID);

        assertGt(sqrtPriceX96, 0, "reference pool not initialized on this fork");
        assertEq(lpFee, REFERENCE_LP_FEE);
        assertGt(manager.getLiquidity(REFERENCE_POOL_ID), 0);

        console.log("fork block", block.number);
        console.log("reference pool tick", tick);

        if (block.number == REFERENCE_BLOCK) {
            assertEq(tick, REFERENCE_BLOCK_TICK, "fork did not include the reference swap");
        }
    }

    function test_fork_searcherPaysCapabilityFee() public {
        _tierSearcher();
        assertEq(swapAndReadFee(mevRouter, 1 ether, 1 ether), SEARCHER_FEE);
    }

    function test_fork_unassignedAgentPaysDefaultFee() public {
        assertEq(swapAndReadFee(swapRouter, 1 ether, 1 ether), DEFAULT_FEE);
    }

    /// @dev proves the mirrored pool reprices the reference trade like the real one did
    function test_fork_mirrorReproducesReferenceSwap() public {
        (, uint256 linkOut) = _searcherSwap();

        console.log("mainnet LINK out", REFERENCE_SWAP_LINK_OUT);
        console.log("mirror  LINK out", linkOut);

        if (block.number == REFERENCE_BLOCK) {
            assertApproxEqRel(linkOut, REFERENCE_SWAP_LINK_OUT, 0.01e18, "mirror diverges from mainnet fill");
        }
    }

    /// @dev same counterparty, same trade, priced before and after the underwriter tiers them
    function test_fork_tierAppliesOnNextSearcherSwap() public {
        uint256 snapshot = vm.snapshotState();

        (uint24 feeBefore, uint256 linkOutBefore) = _searcherSwap();
        assertEq(feeBefore, DEFAULT_FEE, "searcher should start on the default fee");

        vm.revertToState(snapshot);

        _tierSearcher();
        (uint24 feeAfter, uint256 linkOutAfter) = _searcherSwap();

        assertEq(feeAfter, SEARCHER_FEE, "tier did not take effect");
        assertLt(linkOutAfter, linkOutBefore, "searcher kept the same fill after being tiered");

        console.log("LINK out before tiering", linkOutBefore);
        console.log("LINK out after tiering ", linkOutAfter);
        console.log("retained by LPs (LINK) ", linkOutBefore - linkOutAfter);
    }

    function _tierSearcher() internal {
        vm.startPrank(underwriter);
        hook.commitProgram(MEV_SEARCHER_STRUCTURE, MEV_SEARCHER_LOGIC, SEARCHER_FEE);
        hook.assignCapability(MEV_SEARCHER, MEV_BOT);
        hook.assignCapability(MEV_SEARCHER, MEV_BOT_COUNTERPARTY);
        vm.stopPrank();
    }

    /// @dev replays the reference swap size through the counterparty's own address
    function _searcherSwap() internal returns (uint24 fee, uint256 linkOut) {
        uint256 balanceBefore = IERC20Minimal(LINK).balanceOf(address(this));
        fee = swapAndReadFee(mevRouter, REFERENCE_SWAP_ETH_IN, REFERENCE_SWAP_ETH_IN);
        linkOut = IERC20Minimal(LINK).balanceOf(address(this)) - balanceBefore;
    }

    /// @dev opens an ETH/LINK pool with the hook attached at the reference pool's live price
    function _mirrorReferencePool() internal {
        (uint160 sqrtPriceX96, int24 tick,,) = manager.getSlot0(REFERENCE_POOL_ID);
        require(sqrtPriceX96 != 0, "reference pool state unavailable at this block");

        key = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(LINK),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        manager.initialize(key, sqrtPriceX96);

        int24 lower = ((tick / TICK_SPACING) * TICK_SPACING) - (TICK_SPACING * 100);
        int24 upper = ((tick / TICK_SPACING) * TICK_SPACING) + (TICK_SPACING * 100);

        deal(address(this), 500_000 ether);
        deal(LINK, address(this), 20_000_000e18);
        IERC20Minimal(LINK).approve(address(modifyLiquidityRouter), type(uint256).max);
        IERC20Minimal(LINK).approve(address(swapRouter), type(uint256).max);
        IERC20Minimal(LINK).approve(address(mevRouter), type(uint256).max);

        // match the reference pool's depth so marginal pricing is comparable
        uint128 liquidity = manager.getLiquidity(REFERENCE_POOL_ID);

        modifyLiquidityRouter.modifyLiquidity{value: 200_000 ether}(
            key,
            ModifyLiquidityParams({
                tickLower: lower,
                tickUpper: upper,
                liquidityDelta: int256(uint256(liquidity)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }
}
