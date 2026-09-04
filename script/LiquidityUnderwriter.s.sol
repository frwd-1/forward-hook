// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

import {ForwardHook} from "../src/ForwardHook.sol";

/// @author frwd labs
/// @title LiquidityUnderwriter
/// @notice the offchain program that determines an arbitrage trader, named by its own hash
library LiquidityUnderwriter {
    /// @dev keccak256 over the canonical encoding of the finding graph, see frwd/src/gnome/demo
    bytes32 internal constant STRUCTURE_HASH = 0x44f9f03e867632f9410644b6188cc904fe5fcb1650d2e81edfa8570ced5169c4;
    /// @dev keccak256 over the compute sources the graph runs, sealed rather than published
    bytes32 internal constant LOGIC_HASH = 0x6a5de4b2c28827c5b3f3473645475acbd5096cbe8b4bcdc3201af876b97ba84e;

    /// @dev the searcher contract the PoolManager sees as the swap caller
    address internal constant TRADER_SEARCHER = 0x009A8DBaD7000f0000009b002d050058CA881b57;
    /// @dev the EOA that signs and pays for the searcher's transactions
    address internal constant TRADER_SIGNER = 0x004B38217D000000001E4f000034A6F30026Bf1c;

    /// @dev what an unclassified agent pays, matching the pool's own tier
    uint24 internal constant BASE_FEE = 3000;
    /// @dev what a determined arbitrage trader pays instead, a round policy number
    uint24 internal constant ARBITRAGE_FEE = 10_000;

    /// @notice the committed name: structure and logic bound together
    function programHash() internal pure returns (bytes32) {
        return bind(STRUCTURE_HASH, LOGIC_HASH);
    }

    /// @notice recomputes the program name from its two halves
    function bind(bytes32 structureHash, bytes32 logicHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(structureHash, logicHash));
    }

    /// @notice commits the program hash as a capability and prices the agents under it
    function commit(ForwardHook hook, uint24 fee, address[] memory agents) internal returns (bytes32 name) {
        name = hook.commitProgram(STRUCTURE_HASH, LOGIC_HASH, fee);

        for (uint256 i = 0; i < agents.length; i++) {
            hook.assignCapability(name, agents[i]);
        }
    }

    /// @notice the trader determined by the program, as the hook will see them
    function traders() internal pure returns (address[] memory agents) {
        agents = new address[](2);
        agents[0] = TRADER_SEARCHER;
        agents[1] = TRADER_SIGNER;
    }
}

/// @dev commits the arbitrage program hash onchain and tiers the trader it determined
/// @dev forge script script/LiquidityUnderwriter.s.sol --rpc-url $RPC --broadcast
contract Underwrite is Script {
    using LPFeeLibrary for uint24;

    function run() external {
        ForwardHook hook = ForwardHook(vm.envAddress("HOOK"));
        uint24 fee = uint24(vm.envOr("ARBITRAGE_FEE", uint256(LiquidityUnderwriter.ARBITRAGE_FEE)));
        fee.validate();

        bytes32 name = LiquidityUnderwriter.programHash();
        address[] memory agents = LiquidityUnderwriter.traders();

        console.log("hook           ", address(hook));
        console.log("structure hash ");
        console.logBytes32(LiquidityUnderwriter.STRUCTURE_HASH);
        console.log("logic hash     ");
        console.logBytes32(LiquidityUnderwriter.LOGIC_HASH);
        console.log("program hash   ");
        console.logBytes32(name);
        console.log("arbitrage fee  ", fee);

        vm.startBroadcast();
        LiquidityUnderwriter.commit(hook, fee, agents);
        vm.stopBroadcast();

        require(hook.capabilityExists(name), "capability not committed");
        require(hook.capabilityFee(name) == fee, "fee not set");
        for (uint256 i = 0; i < agents.length; i++) {
            require(hook.assignmentOf(agents[i]) == name, "agent not assigned");
            console.log("tiered         ", agents[i]);
        }
    }
}
