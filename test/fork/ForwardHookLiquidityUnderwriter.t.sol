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

import {LiquidityUnderwriter, Underwrite} from "../../script/LiquidityUnderwriter.s.sol";
import {ForwardHookBase} from "../utils/ForwardHookBase.sol";

/// @dev commits the arbitrage program hash onchain, then prices the trader's next real swap with it
contract ForwardHookLiquidityUnderwriterTest is ForwardHookBase {
    using StateLibrary for IPoolManager;

    IPoolManager internal constant MAINNET_POOL_MANAGER = IPoolManager(0x000000000004444c5dc75cB358380D2e3dE08A90);

    /// @dev LIT, 18 decimals
    address internal constant LIT = 0x232CE3bd40fCd6f80f3d55A522d03f25Df784Ee2;

    /// @dev native ETH / LIT, 0.30%, no hooks, one of the pools this trader arbitrages
    PoolId internal constant TRADER_POOL_ID =
        PoolId.wrap(0x0112df46117acf06ac4cfff94a0c250f2bbe0cfe4c83a69815eed28536d5f428);

    /// @dev the atomic arbitrage the program read to determine this trader, see frwd/src/gnome/demo
    bytes32 internal constant DETERMINATION_TX =
        0x6220e15127c49e5c7197be388b2eba363a1d35594a78e4825965a36b1faa9c92;
    uint256 internal constant DETERMINATION_BLOCK = 25327847;

    /// @dev the trader's next trade, tx 0x15e7f05d2ca3ccd1d7275510cc34653351011b05e43b68ac4c9b8eb4e5f7b121
    uint256 internal constant REFERENCE_BLOCK = 25893132;

    /// @dev amounts that transaction's Swap event emitted, the trader paid ETH for LIT
    uint256 internal constant REFERENCE_ETH_IN = 1141014255669864;
    uint256 internal constant REFERENCE_LIT_OUT = 718276977179286053;

    /// @dev fields from that transaction's receipt
    uint256 internal constant REFERENCE_GAS_USED = 481653;
    uint256 internal constant REFERENCE_GAS_PRICE = 58197625;

    /// @dev an address the program never determined, priced as a control
    address internal constant UNRELATED_TRADER = address(uint160(uint256(keccak256("unrelated"))));

    PoolSwapTest internal traderRouter;
    PoolSwapTest internal controlRouter;

    function setUp() public {
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            vm.skip(true);
            return;
        }

        uint256 forkBlock = vm.envOr("ARB_FORK_BLOCK", REFERENCE_BLOCK);
        if (forkBlock == 0) {
            vm.createSelectFork(rpcUrl);
        } else {
            vm.createSelectFork(rpcUrl, forkBlock);
        }

        manager = MAINNET_POOL_MANAGER;

        // the node may have pruned state this far back, in which case there is nothing to fork
        try manager.extsload(bytes32(0)) returns (bytes32) {}
        catch {
            vm.skip(true);
            return;
        }

        swapRouter = new PoolSwapTest(manager);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);

        // stand routers up at the addresses the hook will price, so it sees them as the swap caller
        deployCodeTo("PoolSwapTest.sol:PoolSwapTest", abi.encode(manager), LiquidityUnderwriter.TRADER_SEARCHER);
        traderRouter = PoolSwapTest(LiquidityUnderwriter.TRADER_SEARCHER);

        deployCodeTo("PoolSwapTest.sol:PoolSwapTest", abi.encode(manager), UNRELATED_TRADER);
        controlRouter = PoolSwapTest(UNRELATED_TRADER);

        hook = deployHook();

        _mirrorTraderPool();
    }

    /// @dev the committed name is the two halves bound together, not a constant anyone can pick
    function test_programHashBindsStructureToLogic() public pure {
        bytes32 expected =
            keccak256(abi.encodePacked(LiquidityUnderwriter.STRUCTURE_HASH, LiquidityUnderwriter.LOGIC_HASH));

        assertEq(LiquidityUnderwriter.programHash(), expected, "program hash is not its two halves");
        assertTrue(LiquidityUnderwriter.STRUCTURE_HASH != bytes32(0), "structure hash unset");
        assertTrue(LiquidityUnderwriter.LOGIC_HASH != bytes32(0), "logic hash unset");
    }

    /// @dev changing either half changes the committed name, so the logic cannot be swapped silently
    function test_programHashChangesWithEitherHalf() public pure {
        bytes32 committed = LiquidityUnderwriter.programHash();

        assertTrue(
            LiquidityUnderwriter.bind(bytes32(uint256(1)), LiquidityUnderwriter.LOGIC_HASH) != committed,
            "structure half not bound"
        );
        assertTrue(
            LiquidityUnderwriter.bind(LiquidityUnderwriter.STRUCTURE_HASH, bytes32(uint256(1))) != committed,
            "logic half not bound"
        );
    }

    /// @dev the underwriter commits the hash and it is readable onchain afterwards
    function test_underwriterCommitsProgramHash() public {
        bytes32 name = LiquidityUnderwriter.programHash();

        assertFalse(hook.capabilityExists(name), "capability exists before commit");

        _commitProgram();

        assertTrue(hook.capabilityExists(name), "capability not committed");
        assertEq(hook.capabilityFee(name), LiquidityUnderwriter.ARBITRAGE_FEE, "committed fee wrong");
        assertEq(hook.capabilityAgents(name).length, 2, "expected both trader addresses");
        assertEq(hook.assignmentOf(LiquidityUnderwriter.TRADER_SEARCHER), name, "searcher not tiered");
        assertEq(hook.assignmentOf(LiquidityUnderwriter.TRADER_SIGNER), name, "signer not tiered");

        console.log("committed program hash");
        console.logBytes32(name);
        console.log("arbitrage fee (ppm)", hook.capabilityFee(name));
    }

    /// @dev the deploy script itself commits the hash and tiers the trader
    function test_scriptCommitsProgramOnchain() public {
        Underwrite deployScript = new Underwrite();

        vm.setEnv("HOOK", vm.toString(address(hook)));
        hook.grantRole(hook.UNDERWRITER_ROLE(), DEFAULT_SENDER);

        deployScript.run();

        bytes32 name = LiquidityUnderwriter.programHash();
        assertTrue(hook.capabilityExists(name), "script did not commit the program");
        assertEq(hook.capabilityFee(name), LiquidityUnderwriter.ARBITRAGE_FEE, "script set the wrong fee");
        assertEq(hook.assignmentOf(LiquidityUnderwriter.TRADER_SEARCHER), name, "script did not tier the searcher");

        assertEq(swapAndReadFee(traderRouter, REFERENCE_ETH_IN, REFERENCE_ETH_IN), LiquidityUnderwriter.ARBITRAGE_FEE);
    }

    /// @dev only the underwriter may commit a program
    function test_nonUnderwriterCannotCommitProgram() public {
        vm.expectRevert();
        hook.commitProgram(
            LiquidityUnderwriter.STRUCTURE_HASH, LiquidityUnderwriter.LOGIC_HASH, LiquidityUnderwriter.ARBITRAGE_FEE
        );
    }

    function test_traderPoolIsVisible() public view {
        (uint160 sqrtPriceX96,,, uint24 lpFee) = manager.getSlot0(TRADER_POOL_ID);

        assertGt(sqrtPriceX96, 0, "trader pool not initialized on this fork");
        assertGt(manager.getLiquidity(TRADER_POOL_ID), 0, "trader pool has no liquidity");

        console.log("fork block", block.number);
        console.log("trader pool lp fee (ppm)", lpFee);
    }

    /// @dev the trade being repriced happens after the trade the determination was made from
    function test_repricedTradeComesAfterTheDetermination() public pure {
        assertGt(REFERENCE_BLOCK, DETERMINATION_BLOCK, "reference trade precedes the determination");

        console.log("determined at block", DETERMINATION_BLOCK);
        console.log("determination tx");
        console.logBytes32(DETERMINATION_TX);
        console.log("repriced trade at block", REFERENCE_BLOCK);
        console.log("blocks between", REFERENCE_BLOCK - DETERMINATION_BLOCK);
    }

    /// @dev the same trader, the same trade, priced before and after the program is committed
    function test_feeAppliesOnTradersNextSwap() public {
        uint256 snapshot = vm.snapshotState();

        (uint24 feeBefore, uint256 litOutBefore) = _traderSwap();
        assertEq(feeBefore, DEFAULT_FEE, "trader should start on the default fee");

        vm.revertToState(snapshot);

        _commitProgram();
        (uint24 feeAfter, uint256 litOutAfter) = _traderSwap();

        assertEq(feeAfter, LiquidityUnderwriter.ARBITRAGE_FEE, "committed fee did not take effect");
        assertLt(litOutAfter, litOutBefore, "trader kept the same fill after being tiered");

        console.log("LIT out before commit", litOutBefore);
        console.log("LIT out after commit ", litOutAfter);
        console.log("retained by LPs (LIT)", litOutBefore - litOutAfter);
        console.log("gas the trader paid on the real swap (wei)", referenceGasCost());
    }

    /// @dev the fee is aimed at the determined trader, not at everyone in the pool
    function test_unrelatedTraderStillPaysDefaultFee() public {
        _commitProgram();

        assertEq(_swapAs(controlRouter), DEFAULT_FEE, "control address was repriced");
        assertEq(hook.assignmentOf(UNRELATED_TRADER), bytes32(0), "control address was tiered");
    }

    /// @dev replays the trader's own trade size and reprices it, mirroring the real fill
    function test_mirrorReproducesTradersSwap() public {
        (, uint256 litOut) = _traderSwap();

        console.log("mainnet LIT out", REFERENCE_LIT_OUT);
        console.log("mirror  LIT out", litOut);

        if (block.number == REFERENCE_BLOCK) {
            assertApproxEqRel(litOut, REFERENCE_LIT_OUT, 0.02e18, "mirror diverges from mainnet fill");
        }
    }

    function referenceGasCost() internal pure returns (uint256) {
        return REFERENCE_GAS_USED * REFERENCE_GAS_PRICE;
    }

    function _commitProgram() internal {
        vm.startPrank(underwriter);
        LiquidityUnderwriter.commit(hook, LiquidityUnderwriter.ARBITRAGE_FEE, LiquidityUnderwriter.traders());
        vm.stopPrank();
    }

    /// @dev the trader's real trade size, routed through the address the PoolManager saw
    function _traderSwap() internal returns (uint24 fee, uint256 litOut) {
        uint256 balanceBefore = IERC20Minimal(LIT).balanceOf(address(this));
        fee = swapAndReadFee(traderRouter, REFERENCE_ETH_IN, REFERENCE_ETH_IN);
        litOut = IERC20Minimal(LIT).balanceOf(address(this)) - balanceBefore;
    }

    function _swapAs(PoolSwapTest router) internal returns (uint24 fee) {
        return swapAndReadFee(router, REFERENCE_ETH_IN, REFERENCE_ETH_IN);
    }

    /// @dev opens an ETH/LIT pool with the hook attached at the real pool's live price and depth
    function _mirrorTraderPool() internal {
        (uint160 sqrtPriceX96, int24 tick,,) = manager.getSlot0(TRADER_POOL_ID);
        require(sqrtPriceX96 != 0, "trader pool state unavailable at this block");

        key = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(LIT),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(hook))
        });
        manager.initialize(key, sqrtPriceX96);

        int24 lower = ((tick / TICK_SPACING) * TICK_SPACING) - (TICK_SPACING * 100);
        int24 upper = ((tick / TICK_SPACING) * TICK_SPACING) + (TICK_SPACING * 100);

        deal(address(this), 100_000 ether);
        deal(LIT, address(this), 200_000_000e18);
        IERC20Minimal(LIT).approve(address(modifyLiquidityRouter), type(uint256).max);
        IERC20Minimal(LIT).approve(address(swapRouter), type(uint256).max);
        IERC20Minimal(LIT).approve(address(traderRouter), type(uint256).max);
        IERC20Minimal(LIT).approve(address(controlRouter), type(uint256).max);

        modifyLiquidityRouter.modifyLiquidity{value: 20_000 ether}(
            key,
            ModifyLiquidityParams({
                tickLower: lower,
                tickUpper: upper,
                liquidityDelta: int256(uint256(manager.getLiquidity(TRADER_POOL_ID))),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }
}
