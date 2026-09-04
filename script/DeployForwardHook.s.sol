// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {ForwardHook} from "../src/ForwardHook.sol";

/// @author frwd labs
/// @title DeployForwardHook
/// @notice mines a permission carrying address and deploys the hook against a chosen target
/// @dev TARGET=anvil forge script script/DeployForwardHook.s.sol --rpc-url $RPC --broadcast
contract DeployForwardHook is Script {
    using LPFeeLibrary for uint24;

    /// @dev forge routes salted `new` through this proxy, so it is the deployer the salt must be mined for
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev a fresh chain has no v4, so the target decides whether we deploy a PoolManager or find one
    string internal constant ANVIL = "anvil";
    string internal constant FORK = "fork";
    string internal constant TESTNET = "testnet";

    uint24 internal constant BASE_FEE = 3000;

    error UnknownTarget(string target);
    error PoolManagerUnknown(uint256 chainId);
    error PoolManagerNotDeployed(address poolManager);

    function run() external returns (ForwardHook hook) {
        string memory target = vm.envOr("TARGET", ANVIL);
        address admin = vm.envOr("HOOK_ADMIN", msg.sender);
        address underwriter = vm.envOr("UNDERWRITER", msg.sender);
        uint24 defaultFee = uint24(vm.envOr("DEFAULT_FEE", uint256(BASE_FEE)));
        defaultFee.validate();

        IPoolManager manager = poolManagerFor(target, admin);

        bytes memory args = abi.encode(manager, admin, underwriter, defaultFee);
        (address mined, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, hookFlags(), type(ForwardHook).creationCode, args);

        vm.broadcast();
        hook = new ForwardHook{salt: salt}(manager, admin, underwriter, defaultFee);

        require(address(hook) == mined, "hook address does not match the mined address");
        require(hook.hasRole(hook.DEFAULT_ADMIN_ROLE(), admin), "admin role not held");
        require(hook.hasRole(hook.UNDERWRITER_ROLE(), underwriter), "underwriter role not held");
        require(hook.defaultFee() == defaultFee, "default fee not seeded");

        console.log("target       ", target);
        console.log("chain id     ", block.chainid);
        console.log("pool manager ", address(manager));
        console.log("hook         ", address(hook));
        console.log("hook flags   ", uint160(address(hook)) & Hooks.ALL_HOOK_MASK);
        console.log("salt         ");
        console.logBytes32(salt);
        console.log("admin        ", admin);
        console.log("underwriter  ", underwriter);
        console.log("default fee  ", defaultFee);
    }

    /// @dev the permission bits the mined address has to carry, matched against the hook at construction
    function hookFlags() public pure returns (uint160) {
        return uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG);
    }

    /// @dev anvil starts empty so it gets a fresh PoolManager, a fork or testnet already has the canonical one
    function poolManagerFor(string memory target, address owner) internal returns (IPoolManager) {
        bytes32 kind = keccak256(bytes(target));

        if (kind == keccak256(bytes(ANVIL))) {
            vm.broadcast();
            return IPoolManager(address(new PoolManager(owner)));
        }

        if (kind != keccak256(bytes(FORK)) && kind != keccak256(bytes(TESTNET))) revert UnknownTarget(target);

        address manager = vm.envOr("POOL_MANAGER", canonicalPoolManager(block.chainid));
        if (manager == address(0)) revert PoolManagerUnknown(block.chainid);
        if (manager.code.length == 0) revert PoolManagerNotDeployed(manager);

        return IPoolManager(manager);
    }

    /// @dev canonical v4 PoolManager per chain, zero when this script has no entry for it
    function canonicalPoolManager(uint256 chainId) public pure returns (address) {
        if (chainId == 1) return 0x000000000004444c5dc75cB358380D2e3dE08A90;
        if (chainId == 130) return 0x1F98400000000000000000000000000000000004;
        if (chainId == 8453) return 0x498581fF718922c3f8e6A244956aF099B2652b2b;
        if (chainId == 1301) return 0x00B036B58a818B1BC34d502D3fE730Db729e62AC;
        if (chainId == 11155111) return 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;
        if (chainId == 84532) return 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
        return address(0);
    }
}
