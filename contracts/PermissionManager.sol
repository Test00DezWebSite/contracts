// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "./interfaces/IAuthority.sol";
import "./utils/Mask.sol";

/// @custom:security-contact TODO
contract PermissionManager is
    IAuthority,
    Initializable,
    UUPSUpgradeable,
    Multicall
{
    using Masks for *;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable state-variable-assignment
    Masks.Mask public immutable ADMIN  = 0x00.toMask();

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable state-variable-assignment
    Masks.Mask public immutable PUBLIC = 0xFF.toMask();

    mapping(address =>                   Masks.Mask ) private _permissions;
    mapping(address => mapping(bytes4 => Masks.Mask)) private _restrictions;
    mapping(uint8   =>                   Masks.Mask ) private _admin;

    event GroupAdded(address indexed user, uint8 indexed group);
    event GroupRemoved(address indexed user, uint8 indexed group);
    event GroupAdmins(uint8 indexed group, Masks.Mask admins);
    event Requirements(address indexed target, bytes4 indexed selector, Masks.Mask groups);

    error MissingPermissions(address user, Masks.Mask permissions, Masks.Mask restriction);

    modifier onlyRole(Masks.Mask restriction) {
        address    caller      = msg.sender;
        Masks.Mask permissions = getGroups(caller);

        if (permissions.intersection(restriction).isEmpty()) {
            revert MissingPermissions(caller, permissions, restriction);
        }

        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) public initializer() {
        _setGroupAdmins(0, ADMIN);
        _addGroup(admin, 0);
    }

    // Getters
    function canCall(address caller, address target, bytes4 selector) public view returns (bool) {
        return !getGroups(caller).intersection(getRequirements(target, selector)).isEmpty();
    }

    function getGroups(address user) public view returns (Masks.Mask) {
        return _permissions[user].union(PUBLIC);
    }

    function getGroupAdmins(uint8 group) public view returns (Masks.Mask) {
        return _admin[group].union(ADMIN); // Admin have power over all groups
    }

    function getRequirements(address target, bytes4 selector) public view returns (Masks.Mask) {
        return _restrictions[target][selector].union(ADMIN); // Admins can call an function
    }

    // Group management
    function addGroup(address user, uint8 group) public onlyRole(getGroupAdmins(group)) {
        _addGroup(user, group);
    }

    function remGroup(address user, uint8 group) public onlyRole(getGroupAdmins(group)) {
        _remGroup(user, group);
    }

    function _addGroup(address user, uint8 group) internal {
        _permissions[user] = _permissions[user].union(group.toMask());
        emit GroupAdded(user, group);
    }

    function _remGroup(address user, uint8 group) internal {
        _permissions[user] = _permissions[user].difference(group.toMask());
        emit GroupRemoved(user, group);
    }

    // Group admin management
    function setGroupAdmins(uint8 group, uint8[] calldata admins) public onlyRole(ADMIN) {
        _setGroupAdmins(group, admins.toMask());
    }

    function _setGroupAdmins(uint8 group, Masks.Mask admins) internal {
        _admin[group] = admins;
        emit GroupAdmins(group, admins);
    }

    // Requirement management
    function setRequirements(address target, bytes4[] calldata selectors, uint8[] calldata groups) public onlyRole(ADMIN) {
        Masks.Mask mask = groups.toMask();
        for (uint256 i = 0; i < selectors.length; ++i) {
            _setRequirements(target, selectors[i], mask);
        }
    }

    function _setRequirements(address target, bytes4 selector, Masks.Mask groups) internal {
        _restrictions[target][selector] = groups;
        emit Requirements(target, selector, groups);
    }

    // upgradeability
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(ADMIN) {}
}
