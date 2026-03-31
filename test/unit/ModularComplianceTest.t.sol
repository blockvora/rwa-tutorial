// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {ModularCompliance} from "../../src/compliance/ModularCompliance.sol";
import {IModularCompliance} from "../../src/compliance/interfaces/IModularCompliance.sol";
import {AccreditedInvestorModule} from "../../src/compliance/modules/AccreditedInvestorModule.sol";
import {MaxBalanceModule} from "../../src/compliance/modules/MaxBalanceModule.sol";
import {TransferLimitModule} from "../../src/compliance/modules/TransferLimitModule.sol";
import {IdentityRegistry} from "../../src/identity/IdentityRegistry.sol";
import {MockIdentity} from "../../src/identity/mocks/MockIdentity.sol";

/**
 * @title ModularComplianceTest
 * @notice Comprehensive tests for ModularCompliance orchestrator
 */
contract ModularComplianceTest is Test {
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    ModularCompliance public compliance;
    IdentityRegistry public identityRegistry;

    AccreditedInvestorModule public accreditedModule;
    MaxBalanceModule public maxBalanceModule;
    TransferLimitModule public transferLimitModule;

    address public owner;
    address public token;
    address public investor1;
    address public investor2;

    MockIdentity public identity1;
    MockIdentity public identity2;

    // Test constants
    uint256 public constant MAX_BALANCE = 1_000_000e18; // 1M tokens
    uint256 public constant DAILY_LIMIT = 100_000e18; // 100K tokens per day

    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    function setUp() public {
        owner = makeAddr("owner");
        token = makeAddr("token");
        investor1 = makeAddr("investor1");
        investor2 = makeAddr("investor2");

        // Deploy identity registry
        vm.prank(owner);
        identityRegistry = new IdentityRegistry();

        // Deploy compliance
        vm.prank(owner);
        compliance = new ModularCompliance();

        // Deploy modules
        accreditedModule = new AccreditedInvestorModule(address(identityRegistry));
        maxBalanceModule = new MaxBalanceModule(address(identityRegistry), MAX_BALANCE);
        transferLimitModule = new TransferLimitModule(address(identityRegistry), DAILY_LIMIT);

        // Create and register identities
        identity1 = new MockIdentity(investor1);
        identity2 = new MockIdentity(investor2);

        vm.startPrank(owner);
        identityRegistry.grantRole(AGENT_ROLE, owner);
        identityRegistry.registerIdentity(investor1, identity1, 840); // USA
        identityRegistry.registerIdentity(investor2, identity2, 840);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment() public view {
        assertEq(compliance.owner(), owner);
        assertEq(compliance.getTokenBound(), address(0));
        assertEq(compliance.getModules().length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN BINDING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BindToken() public {
        vm.prank(owner);
        compliance.bindToken(token);

        assertEq(compliance.getTokenBound(), token);
    }

    function test_BindToken_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit IModularCompliance.TokenBound(token);

        vm.prank(owner);
        compliance.bindToken(token);
    }

    function test_BindToken_RevertsIfNotOwner() public {
        vm.expectRevert();
        vm.prank(investor1);
        compliance.bindToken(token);
    }

    function test_BindToken_RevertsIfZeroAddress() public {
        vm.expectRevert("ModularCompliance: invalid token address");
        vm.prank(owner);
        compliance.bindToken(address(0));
    }

    function test_UnbindToken() public {
        vm.startPrank(owner);
        compliance.bindToken(token);
        compliance.unbindToken(token);
        vm.stopPrank();

        assertEq(compliance.getTokenBound(), address(0));
    }

    function test_UnbindToken_EmitsEvent() public {
        vm.prank(owner);
        compliance.bindToken(token);

        vm.expectEmit(true, false, false, false);
        emit IModularCompliance.TokenUnbound(token);

        vm.prank(owner);
        compliance.unbindToken(token);
    }

    /*//////////////////////////////////////////////////////////////
                      MODULE MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AddModule() public {
        vm.prank(owner);
        compliance.addModule(address(accreditedModule));

        assertTrue(compliance.isModuleBound(address(accreditedModule)));
        assertEq(compliance.getModules().length, 1);
        assertEq(compliance.getModules()[0], address(accreditedModule));
    }

    function test_AddModule_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit IModularCompliance.ModuleAdded(address(accreditedModule));

        vm.prank(owner);
        compliance.addModule(address(accreditedModule));
    }

    function test_AddModule_RevertsIfNotOwner() public {
        vm.expectRevert();
        vm.prank(investor1);
        compliance.addModule(address(accreditedModule));
    }

    function test_AddModule_RevertsIfZeroAddress() public {
        vm.expectRevert("ModularCompliance: invalid module address");
        vm.prank(owner);
        compliance.addModule(address(0));
    }

    function test_AddModule_RevertsIfAlreadyBound() public {
        vm.startPrank(owner);
        compliance.addModule(address(accreditedModule));

        vm.expectRevert("ModularCompliance: module already bound");
        compliance.addModule(address(accreditedModule));
        vm.stopPrank();
    }

    function test_AddMultipleModules() public {
        vm.startPrank(owner);
        compliance.addModule(address(accreditedModule));
        compliance.addModule(address(maxBalanceModule));
        compliance.addModule(address(transferLimitModule));
        vm.stopPrank();

        assertEq(compliance.getModules().length, 3);
        assertTrue(compliance.isModuleBound(address(accreditedModule)));
        assertTrue(compliance.isModuleBound(address(maxBalanceModule)));
        assertTrue(compliance.isModuleBound(address(transferLimitModule)));
    }

    function test_RemoveModule() public {
        vm.startPrank(owner);
        compliance.addModule(address(accreditedModule));
        compliance.removeModule(address(accreditedModule));
        vm.stopPrank();

        assertFalse(compliance.isModuleBound(address(accreditedModule)));
        assertEq(compliance.getModules().length, 0);
    }

    function test_RemoveModule_EmitsEvent() public {
        vm.prank(owner);
        compliance.addModule(address(accreditedModule));

        vm.expectEmit(true, false, false, false);
        emit IModularCompliance.ModuleRemoved(address(accreditedModule));

        vm.prank(owner);
        compliance.removeModule(address(accreditedModule));
    }

    function test_RemoveModule_RevertsIfNotBound() public {
        vm.expectRevert("ModularCompliance: module not bound");
        vm.prank(owner);
        compliance.removeModule(address(accreditedModule));
    }

    function test_RemoveModule_FromMiddle() public {
        vm.startPrank(owner);
        compliance.addModule(address(accreditedModule));
        compliance.addModule(address(maxBalanceModule));
        compliance.addModule(address(transferLimitModule));

        // Remove middle module
        compliance.removeModule(address(maxBalanceModule));
        vm.stopPrank();

        assertEq(compliance.getModules().length, 2);
        assertTrue(compliance.isModuleBound(address(accreditedModule)));
        assertFalse(compliance.isModuleBound(address(maxBalanceModule)));
        assertTrue(compliance.isModuleBound(address(transferLimitModule)));
    }

    /*//////////////////////////////////////////////////////////////
                      COMPLIANCE CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CanTransfer_NoModules() public {
        // With no modules, all transfers allowed
        bool canTransfer = compliance.canTransfer(investor1, investor2, 1000e18);
        assertTrue(canTransfer);
    }

    function test_CanTransfer_WithAccreditedModule() public {
        vm.prank(owner);
        compliance.addModule(address(accreditedModule));

        // Both investors are registered, so transfer allowed
        bool canTransfer = compliance.canTransfer(investor1, investor2, 1000e18);
        assertTrue(canTransfer);
    }

    function test_CanTransfer_FailsIfReceiverNotVerified() public {
        vm.prank(owner);
        compliance.addModule(address(accreditedModule));

        address unverified = makeAddr("unverified");

        // Unverified receiver should fail
        bool canTransfer = compliance.canTransfer(investor1, unverified, 1000e18);
        assertFalse(canTransfer);
    }

    function test_CanTransfer_WithMaxBalanceModule() public {
        vm.prank(owner);
        compliance.addModule(address(maxBalanceModule));

        // Transfer within limit should pass
        bool canTransfer = compliance.canTransfer(investor1, investor2, 500_000e18);
        assertTrue(canTransfer);

        // Transfer exceeding limit should fail
        canTransfer = compliance.canTransfer(investor1, investor2, 1_500_000e18);
        assertFalse(canTransfer);
    }

    function test_CanTransfer_WithMultipleModules() public {
        vm.startPrank(owner);
        compliance.addModule(address(accreditedModule));
        compliance.addModule(address(maxBalanceModule));
        vm.stopPrank();

        // Both checks must pass
        bool canTransfer = compliance.canTransfer(investor1, investor2, 500_000e18);
        assertTrue(canTransfer);
    }

    function test_CanTransfer_FailsIfAnyModuleRejects() public {
        vm.startPrank(owner);
        compliance.addModule(address(accreditedModule));
        compliance.addModule(address(maxBalanceModule));
        vm.stopPrank();

        // Accredited check passes, but max balance fails
        bool canTransfer = compliance.canTransfer(investor1, investor2, 1_500_000e18);
        assertFalse(canTransfer);
    }

    /*//////////////////////////////////////////////////////////////
                      STATE UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Transferred_UpdatesModuleState() public {
        // Bind token and add module
        vm.startPrank(owner);
        compliance.bindToken(token);
        compliance.addModule(address(maxBalanceModule));
        vm.stopPrank();

        // Simulate mint to investor1
        vm.prank(token);
        compliance.created(investor1, 1_000_000e18);

        // Check balance
        assertEq(maxBalanceModule.getWalletBalance(investor1), 1_000_000e18);

        // Simulate transfer
        vm.prank(token);
        compliance.transferred(investor1, investor2, 500_000e18);

        // Check balances updated
        assertEq(maxBalanceModule.getWalletBalance(investor1), 500_000e18);
        assertEq(maxBalanceModule.getWalletBalance(investor2), 500_000e18);
    }

    function test_Transferred_RevertsIfNotToken() public {
        vm.prank(owner);
        compliance.bindToken(token);

        vm.expectRevert("ModularCompliance: caller is not the bound token");
        vm.prank(investor1);
        compliance.transferred(investor1, investor2, 1000e18);
    }

    function test_Transferred_RevertsIfInvalidAddresses() public {
        vm.prank(owner);
        compliance.bindToken(token);

        vm.expectRevert("ModularCompliance: invalid addresses");
        vm.prank(token);
        compliance.transferred(address(0), investor2, 1000e18);
    }

    function test_Transferred_RevertsIfZeroAmount() public {
        vm.prank(owner);
        compliance.bindToken(token);

        vm.expectRevert("ModularCompliance: invalid amount");
        vm.prank(token);
        compliance.transferred(investor1, investor2, 0);
    }

    function test_Created_UpdatesModuleState() public {
        vm.startPrank(owner);
        compliance.bindToken(token);
        compliance.addModule(address(maxBalanceModule));
        vm.stopPrank();

        vm.prank(token);
        compliance.created(investor1, 1_000_000e18);

        assertEq(maxBalanceModule.getWalletBalance(investor1), 1_000_000e18);
    }

    function test_Destroyed_UpdatesModuleState() public {
        vm.startPrank(owner);
        compliance.bindToken(token);
        compliance.addModule(address(maxBalanceModule));
        vm.stopPrank();

        // Mint first
        vm.prank(token);
        compliance.created(investor1, 1_000_000e18);

        // Then burn
        vm.prank(token);
        compliance.destroyed(investor1, 500_000e18);

        assertEq(maxBalanceModule.getWalletBalance(investor1), 500_000e18);
    }

    /*//////////////////////////////////////////////////////////////
                      INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CompleteTransferFlow() public {
        // Setup: Bind token and add modules
        vm.startPrank(owner);
        compliance.bindToken(token);
        compliance.addModule(address(accreditedModule));
        compliance.addModule(address(maxBalanceModule));
        compliance.addModule(address(transferLimitModule));
        vm.stopPrank();

        // Mint to investor1
        vm.prank(token);
        compliance.created(investor1, 1_000_000e18);

        // Check can transfer
        assertTrue(compliance.canTransfer(investor1, investor2, 50_000e18));

        // Execute transfer
        vm.prank(token);
        compliance.transferred(investor1, investor2, 50_000e18);

        // Verify state updated
        assertEq(maxBalanceModule.getWalletBalance(investor1), 950_000e18);
        assertEq(maxBalanceModule.getWalletBalance(investor2), 50_000e18);
        assertEq(transferLimitModule.getTodayVolume(investor1), 50_000e18);
    }

    function test_MultipleTransfersRespectDailyLimit() public {
        vm.startPrank(owner);
        compliance.bindToken(token);
        compliance.addModule(address(transferLimitModule));
        vm.stopPrank();

        // Mint to investor1
        vm.prank(token);
        compliance.created(investor1, 1_000_000e18);

        // First transfer: 60K (within limit)
        assertTrue(compliance.canTransfer(investor1, investor2, 60_000e18));
        vm.prank(token);
        compliance.transferred(investor1, investor2, 60_000e18);

        // Second transfer: 30K (total 90K, still within 100K limit)
        assertTrue(compliance.canTransfer(investor1, investor2, 30_000e18));
        vm.prank(token);
        compliance.transferred(investor1, investor2, 30_000e18);

        // Third transfer: 20K (would be 110K total, exceeds limit)
        assertFalse(compliance.canTransfer(investor1, investor2, 20_000e18));
    }

    function test_DailyLimitResetsNextDay() public {
        vm.startPrank(owner);
        compliance.bindToken(token);
        compliance.addModule(address(transferLimitModule));
        vm.stopPrank();

        vm.prank(token);
        compliance.created(investor1, 1_000_000e18);

        // Transfer 100K today
        vm.prank(token);
        compliance.transferred(investor1, investor2, 100_000e18);

        // Cannot transfer more today
        assertFalse(compliance.canTransfer(investor1, investor2, 1e18));

        // Warp to next day
        vm.warp(block.timestamp + 1 days);

        // Can transfer again
        assertTrue(compliance.canTransfer(investor1, investor2, 100_000e18));
    }
}
