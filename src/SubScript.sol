// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @author frwd labs

abstract contract SubScript is AccessControl {
    /// @notice role for risk underwriter to create capabilities
    bytes32 public constant UNDERWRITER_ROLE = keccak256("UNDERWRITER_ROLE");
    /// TODO: NOT SURE I WANT TO HARDCODE THIS
    bytes32 public constant LP_ROLE = keccak256("LP_ROLE");

    /// TODO MAYBE CALL THESE CAPABILITIES? OR..?
    /// TODO: CAN WE MAKE THIS UNIVERSAL? I GUESS WE NEED ACCOUNTS AND CAPABILITIES?
    /// @notice name is a hashed value
    struct Capability {
        bytes32 name;
        uint24 fee;
        bool exists;
        /// TODO: NOT SURE I NEED THIS
        address[] addresses;
    }
    /// TODO: DOUBLE CHECK THIS
    mapping(bytes32 => Capability) internal capabilities;
    mapping(address => bytes32) internal assignments;

    constructor(address _underwriter) {
        _grantRole(UNDERWRITER_ROLE, _underwriter);
    }

    /// TODO: FUNCTION UPDATE UNDERWRITER ROLE?

    /// TODO: UPDATE STORAGE MODIFIERS?
    function createCapability(
        bytes32 name,
        uint24 fee
    ) public onlyRole(UNDERWRITER_ROLE) {
        capabilities[name] = Capability({
            name: name,
            fee: fee,
            exists: true,
            addresses: new address[](0)
        });
    }

    /// TODO: UPDATE STORAGE MODIFIERS?
    function updateCapabilityFee(
        bytes32 name,
        uint24 fee
    ) public onlyRole(LP_ROLE) {
        capabilities[name].fee = fee;
    }

    /// TODO: UPDATE STORAGE MODIFIERS?
    function assignCapability(
        bytes32 name,
        address _address
    ) public onlyRole(UNDERWRITER_ROLE) {
        /// TODO: FEELS A BIT OFF
        assignments[_address] = name;
        capabilities[name].addresses.push(_address);
    }

    /// TODO: UNDERWRITER FEES?
}
