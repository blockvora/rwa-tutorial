// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {IdentityRegistry} from "../../src/identity/IdentityRegistry.sol";
import {IIdentityRegistry} from "../../src/identity/interfaces/IIdentityRegistry.sol";
import {IIdentity} from "../../src/identity/interfaces/IIdentity.sol";
import {MockIdentity} from "../../src/identity/mocks/MockIdentity.sol";

/**
 * @title IdentityRegistryTest
 * @notice Comprehensive tests for the IdentityRegistry contract
 * @dev Tests Phase 1 functionality (basic registration and verification)
 */
contract IdentityRegistryTest is Test {
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    IdentityRegistry public registry;

    address public admin;
    address public agent;
    address public investor1;
    address public investor2;
    address public unauthorized;

    MockIdentity public identity1;
    MockIdentity public identity2;

    // Country codes (ISO 3166-1 numeric)
    uint16 public constant USA = 840;
    uint16 public constant CANADA = 124;
    uint16 public constant UK = 826;

    // Role identifiers
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    function setUp() public {
        // Create test accounts
        admin = makeAddr("admin");
        agent = makeAddr("agent");
        investor1 = makeAddr("investor1");
        investor2 = makeAddr("investor2");
        unauthorized = makeAddr("unauthorized");

        // Deploy registry as admin
        vm.prank(admin);
        registry = new IdentityRegistry();

        // Grant agent role
        vm.prank(admin);
        registry.grantRole(AGENT_ROLE, agent);

        // Create mock identities
        identity1 = new MockIdentity(investor1);
        identity2 = new MockIdentity(investor2);
    }

    /*//////////////////////////////////////////////////////////////
                          DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment() public view {
        // Admin should have admin role
        assertTrue(registry.hasRole(DEFAULT_ADMIN_ROLE, admin));

        // Admin should also have agent role (from constructor)
        assertTrue(registry.hasRole(AGENT_ROLE, admin));
    }

    function test_AgentRoleGranted() public view {
        // Agent should have agent role
        assertTrue(registry.hasRole(AGENT_ROLE, agent));

        // Agent should NOT have admin role
        assertFalse(registry.hasRole(DEFAULT_ADMIN_ROLE, agent));
    }

    /*//////////////////////////////////////////////////////////////
                      REGISTER IDENTITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RegisterIdentity() public {
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        // Check identity is registered
        assertEq(address(registry.identity(investor1)), address(identity1));

        // Check country is set
        assertEq(registry.investorCountry(investor1), USA);

        // Check contains returns true
        assertTrue(registry.contains(investor1));

        // Check isVerified returns true (Phase 1)
        assertTrue(registry.isVerified(investor1));
    }

    function test_RegisterIdentity_EmitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit IIdentityRegistry.IdentityRegistered(investor1, identity1);

        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);
    }

    function test_RegisterIdentity_RevertsIfNotAgent() public {
        vm.expectRevert();
        vm.prank(unauthorized);
        registry.registerIdentity(investor1, identity1, USA);
    }

    function test_RegisterIdentity_RevertsIfZeroWallet() public {
        vm.expectRevert("IdentityRegistry: invalid wallet address");
        vm.prank(agent);
        registry.registerIdentity(address(0), identity1, USA);
    }

    function test_RegisterIdentity_RevertsIfZeroIdentity() public {
        vm.expectRevert("IdentityRegistry: invalid identity address");
        vm.prank(agent);
        registry.registerIdentity(investor1, IIdentity(address(0)), USA);
    }

    function test_RegisterIdentity_RevertsIfAlreadyRegistered() public {
        // Register once
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        // Try to register again
        vm.expectRevert("IdentityRegistry: identity already registered");
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);
    }

    function test_RegisterMultipleIdentities() public {
        vm.startPrank(agent);
        registry.registerIdentity(investor1, identity1, USA);
        registry.registerIdentity(investor2, identity2, CANADA);
        vm.stopPrank();

        // Check both are registered
        assertTrue(registry.isVerified(investor1));
        assertTrue(registry.isVerified(investor2));

        // Check countries are correct
        assertEq(registry.investorCountry(investor1), USA);
        assertEq(registry.investorCountry(investor2), CANADA);
    }

    /*//////////////////////////////////////////////////////////////
                      UPDATE IDENTITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UpdateIdentity() public {
        // Register initial identity
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        // Create new identity
        MockIdentity newIdentity = new MockIdentity(investor1);

        // Update to new identity
        vm.prank(agent);
        registry.updateIdentity(investor1, newIdentity);

        // Check identity is updated
        assertEq(address(registry.identity(investor1)), address(newIdentity));

        // Country should remain the same
        assertEq(registry.investorCountry(investor1), USA);
    }

    function test_UpdateIdentity_EmitsEvent() public {
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        MockIdentity newIdentity = new MockIdentity(investor1);

        vm.expectEmit(true, true, true, false);
        emit IIdentityRegistry.IdentityUpdated(investor1, identity1, newIdentity);

        vm.prank(agent);
        registry.updateIdentity(investor1, newIdentity);
    }

    function test_UpdateIdentity_RevertsIfNotAgent() public {
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        MockIdentity newIdentity = new MockIdentity(investor1);

        vm.expectRevert();
        vm.prank(unauthorized);
        registry.updateIdentity(investor1, newIdentity);
    }

    function test_UpdateIdentity_RevertsIfNotRegistered() public {
        MockIdentity newIdentity = new MockIdentity(investor1);

        vm.expectRevert("IdentityRegistry: identity not registered");
        vm.prank(agent);
        registry.updateIdentity(investor1, newIdentity);
    }

    function test_UpdateIdentity_RevertsIfZeroIdentity() public {
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        vm.expectRevert("IdentityRegistry: invalid identity address");
        vm.prank(agent);
        registry.updateIdentity(investor1, IIdentity(address(0)));
    }

    /*//////////////////////////////////////////////////////////////
                      UPDATE COUNTRY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UpdateCountry() public {
        // Register with USA
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        // Update to UK
        vm.prank(agent);
        registry.updateCountry(investor1, UK);

        // Check country is updated
        assertEq(registry.investorCountry(investor1), UK);

        // Identity should remain the same
        assertEq(address(registry.identity(investor1)), address(identity1));
    }

    function test_UpdateCountry_EmitsEvent() public {
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        vm.expectEmit(true, true, false, false);
        emit IIdentityRegistry.CountryUpdated(investor1, UK);

        vm.prank(agent);
        registry.updateCountry(investor1, UK);
    }

    function test_UpdateCountry_RevertsIfNotAgent() public {
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        vm.expectRevert();
        vm.prank(unauthorized);
        registry.updateCountry(investor1, UK);
    }

    function test_UpdateCountry_RevertsIfNotRegistered() public {
        vm.expectRevert("IdentityRegistry: identity not registered");
        vm.prank(agent);
        registry.updateCountry(investor1, UK);
    }

    /*//////////////////////////////////////////////////////////////
                      DELETE IDENTITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DeleteIdentity() public {
        // Register identity
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        // Verify it's registered
        assertTrue(registry.isVerified(investor1));

        // Delete identity
        vm.prank(agent);
        registry.deleteIdentity(investor1);

        // Check identity is removed
        assertEq(address(registry.identity(investor1)), address(0));

        // Check country is removed
        assertEq(registry.investorCountry(investor1), 0);

        // Check contains returns false
        assertFalse(registry.contains(investor1));

        // Check isVerified returns false
        assertFalse(registry.isVerified(investor1));
    }

    function test_DeleteIdentity_EmitsEvent() public {
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        vm.expectEmit(true, true, false, false);
        emit IIdentityRegistry.IdentityRemoved(investor1, identity1);

        vm.prank(agent);
        registry.deleteIdentity(investor1);
    }

    function test_DeleteIdentity_RevertsIfNotAgent() public {
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        vm.expectRevert();
        vm.prank(unauthorized);
        registry.deleteIdentity(investor1);
    }

    function test_DeleteIdentity_RevertsIfNotRegistered() public {
        vm.expectRevert("IdentityRegistry: identity not registered");
        vm.prank(agent);
        registry.deleteIdentity(investor1);
    }

    /*//////////////////////////////////////////////////////////////
                      VERIFICATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsVerified_ReturnsFalseForUnregistered() public view {
        assertFalse(registry.isVerified(investor1));
    }

    function test_IsVerified_ReturnsTrueForRegistered() public {
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        assertTrue(registry.isVerified(investor1));
    }

    function test_IsVerified_ReturnsFalseAfterDeletion() public {
        vm.startPrank(agent);
        registry.registerIdentity(investor1, identity1, USA);
        registry.deleteIdentity(investor1);
        vm.stopPrank();

        assertFalse(registry.isVerified(investor1));
    }

    function test_Contains_ReturnsFalseForUnregistered() public view {
        assertFalse(registry.contains(investor1));
    }

    function test_Contains_ReturnsTrueForRegistered() public {
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        assertTrue(registry.contains(investor1));
    }

    /*//////////////////////////////////////////////////////////////
                      VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Identity_ReturnsZeroForUnregistered() public view {
        assertEq(address(registry.identity(investor1)), address(0));
    }

    function test_Identity_ReturnsCorrectAddress() public {
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        assertEq(address(registry.identity(investor1)), address(identity1));
    }

    function test_InvestorCountry_ReturnsZeroForUnregistered() public view {
        assertEq(registry.investorCountry(investor1), 0);
    }

    function test_InvestorCountry_ReturnsCorrectCode() public {
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        assertEq(registry.investorCountry(investor1), USA);
    }

    function test_ClaimTopicsRegistry_ReturnsZeroInitially() public view {
        assertEq(address(registry.claimTopicsRegistry()), address(0));
    }

    function test_TrustedIssuersRegistry_ReturnsZeroInitially() public view {
        assertEq(address(registry.trustedIssuersRegistry()), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                      ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetClaimTopicsRegistry() public {
        address mockRegistry = makeAddr("claimTopicsRegistry");

        vm.prank(admin);
        registry.setClaimTopicsRegistry(mockRegistry);

        assertEq(address(registry.claimTopicsRegistry()), mockRegistry);
    }

    function test_SetClaimTopicsRegistry_RevertsIfNotAdmin() public {
        address mockRegistry = makeAddr("claimTopicsRegistry");

        vm.expectRevert();
        vm.prank(agent);
        registry.setClaimTopicsRegistry(mockRegistry);
    }

    function test_SetTrustedIssuersRegistry() public {
        address mockRegistry = makeAddr("trustedIssuersRegistry");

        vm.prank(admin);
        registry.setTrustedIssuersRegistry(mockRegistry);

        assertEq(address(registry.trustedIssuersRegistry()), mockRegistry);
    }

    function test_SetTrustedIssuersRegistry_RevertsIfNotAdmin() public {
        address mockRegistry = makeAddr("trustedIssuersRegistry");

        vm.expectRevert();
        vm.prank(agent);
        registry.setTrustedIssuersRegistry(mockRegistry);
    }

    /*//////////////////////////////////////////////////////////////
                      ROLE MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AdminCanGrantAgentRole() public {
        address newAgent = makeAddr("newAgent");

        vm.prank(admin);
        registry.grantRole(AGENT_ROLE, newAgent);

        assertTrue(registry.hasRole(AGENT_ROLE, newAgent));
    }

    function test_AdminCanRevokeAgentRole() public {
        vm.prank(admin);
        registry.revokeRole(AGENT_ROLE, agent);

        assertFalse(registry.hasRole(AGENT_ROLE, agent));
    }

    function test_AgentCannotGrantRoles() public {
        address newAgent = makeAddr("newAgent");

        vm.expectRevert();
        vm.prank(agent);
        registry.grantRole(AGENT_ROLE, newAgent);
    }

    /*//////////////////////////////////////////////////////////////
                      INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CompleteInvestorLifecycle() public {
        // 1. Register investor
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);
        assertTrue(registry.isVerified(investor1));

        // 2. Update country (investor relocates)
        vm.prank(agent);
        registry.updateCountry(investor1, CANADA);
        assertEq(registry.investorCountry(investor1), CANADA);

        // 3. Update identity (switches KYC provider)
        MockIdentity newIdentity = new MockIdentity(investor1);
        vm.prank(agent);
        registry.updateIdentity(investor1, newIdentity);
        assertEq(address(registry.identity(investor1)), address(newIdentity));

        // 4. Delete identity (loses eligibility)
        vm.prank(agent);
        registry.deleteIdentity(investor1);
        assertFalse(registry.isVerified(investor1));
    }

    function test_MultipleAgentsCanManageRegistry() public {
        address agent2 = makeAddr("agent2");

        // Admin grants role to second agent
        vm.prank(admin);
        registry.grantRole(AGENT_ROLE, agent2);

        // Both agents can register identities
        vm.prank(agent);
        registry.registerIdentity(investor1, identity1, USA);

        vm.prank(agent2);
        registry.registerIdentity(investor2, identity2, CANADA);

        assertTrue(registry.isVerified(investor1));
        assertTrue(registry.isVerified(investor2));
    }
}
