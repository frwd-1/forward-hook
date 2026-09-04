// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

/// @author frwd labs

abstract contract SubScript is AccessControl {
    using LPFeeLibrary for uint24;

    /// @notice role for risk underwriter to create capabilities
    bytes32 public constant UNDERWRITER_ROLE = keccak256("UNDERWRITER_ROLE");
    /// @notice role for LPs to reprice committed capabilities
    bytes32 public constant LP_ROLE = keccak256("LP_ROLE");

    /// @notice name is a hashed value
    struct Capability {
        bytes32 name;
        uint24 fee;
        bool exists;
        address[] addresses;
    }
    /// @notice the two halves a committed name binds together
    struct Program {
        bytes32 structureHash;
        bytes32 logicHash;
    }

    mapping(bytes32 => Capability) internal capabilities;
    mapping(address => bytes32) internal assignments;
    mapping(bytes32 => Program) internal programs;

    error InvalidProgram();

    /// @notice fee charged to agents holding no capability
    uint24 public defaultFee;

    /// @notice the underwriter committed a capability, named by the hash of the logic behind it
    event CapabilityCommitted(bytes32 indexed name, uint24 fee);
    /// @notice an agent was placed under a committed capability
    event CapabilityAssigned(bytes32 indexed name, address indexed agent);
    /// @notice the halves behind a priced capability, published so the fee can be audited
    event ProgramCommitted(bytes32 indexed name, bytes32 structureHash, bytes32 logicHash);

    constructor(address _underwriter, uint24 _defaultFee) {
        _grantRole(UNDERWRITER_ROLE, _underwriter);
        _setDefaultFee(_defaultFee);
    }

    function _setDefaultFee(uint24 fee) internal {
        fee.validate();
        defaultFee = fee;
    }

    /// @notice the name a program is priced under, bound from the two halves it is made of
    function bindProgram(
        bytes32 structureHash,
        bytes32 logicHash
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(structureHash, logicHash));
    }

    /// @notice prices a capability by the program behind it, so the fee can be rebound and audited
    function commitProgram(
        bytes32 structureHash,
        bytes32 logicHash,
        uint24 fee
    ) public onlyRole(UNDERWRITER_ROLE) returns (bytes32 name) {
        if (structureHash == bytes32(0) || logicHash == bytes32(0)) revert InvalidProgram();

        name = bindProgram(structureHash, logicHash);

        /// @dev repricing keeps the agents already placed under the name
        if (capabilities[name].exists) {
            capabilities[name].fee = fee;
            emit CapabilityCommitted(name, fee);
        } else {
            _createCapability(name, fee);
        }

        programs[name] = Program({structureHash: structureHash, logicHash: logicHash});
        emit ProgramCommitted(name, structureHash, logicHash);
    }

    function _createCapability(bytes32 name, uint24 fee) internal {
        capabilities[name] = Capability({
            name: name,
            fee: fee,
            exists: true,
            addresses: new address[](0)
        });
        emit CapabilityCommitted(name, fee);
    }

    /// @notice LPs reprice a committed capability
    function updateCapabilityFee(
        bytes32 name,
        uint24 fee
    ) public onlyRole(LP_ROLE) {
        capabilities[name].fee = fee;
    }

    /// @notice places an agent under a committed capability
    function assignCapability(
        bytes32 name,
        address _address
    ) public onlyRole(UNDERWRITER_ROLE) {
        assignments[_address] = name;
        capabilities[name].addresses.push(_address);
        emit CapabilityAssigned(name, _address);
    }

    /// @notice whether the underwriter has committed this capability
    function capabilityExists(bytes32 name) external view returns (bool) {
        return capabilities[name].exists;
    }

    /// @notice fee charged to agents holding this capability
    function capabilityFee(bytes32 name) external view returns (uint24) {
        return capabilities[name].fee;
    }

    /// @notice the halves published behind a priced capability, zero when the name was never committed
    function programOf(
        bytes32 name
    ) external view returns (bytes32 structureHash, bytes32 logicHash) {
        Program memory program = programs[name];
        return (program.structureHash, program.logicHash);
    }

    /// @notice the fee a held structure and logic are priced at, reverting when they bind to nothing
    function programFee(
        bytes32 structureHash,
        bytes32 logicHash
    ) external view returns (uint24) {
        bytes32 name = bindProgram(structureHash, logicHash);
        if (!capabilities[name].exists) revert InvalidProgram();
        return capabilities[name].fee;
    }

    /// @notice every agent placed under this capability
    function capabilityAgents(
        bytes32 name
    ) external view returns (address[] memory) {
        return capabilities[name].addresses;
    }

    /// @notice the capability an agent is priced under, zero if none
    function assignmentOf(address agent) external view returns (bytes32) {
        return assignments[agent];
    }

    /// @notice fee the agent is priced at under their assigned capability
    function underwriterFee(address agent) external view returns (uint24) {
        return capabilities[assignments[agent]].fee;
    }

    /// @notice reprices the whole capability the agent is assigned to
    function setUnderwriterFee(
        address agent,
        uint24 fee
    ) external onlyRole(LP_ROLE) {
        capabilities[assignments[agent]].fee = fee;
    }
}
