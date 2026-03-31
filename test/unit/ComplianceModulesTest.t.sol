// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {AccreditedInvestorModule} from "../../src/compliance/modules/AccreditedInvestorModule.sol";
import {MaxBalanceModule} from "../../src/compliance/modules/MaxBalanceModule.sol";
import {TransferLimitModule} from "../../src/compliance/modules/TransferLimitModule.sol";
import {IdentityRegistry} from "../../src/identity/IdentityRegistry.sol";
import {MockIdentity} from "../../src/identity/mocks/MockIdentity.sol";
import {IModule} from "../../src/compliance/interfaces/IModule.sol";

/**
 * @title ComplianceModulesTest
 * @notice Tests for individual compliance modules
 */
contract ComplianceModulesTest is Test {
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    IdentityRegistry public identityRegistry;
    AccreditedInvestorModule public accreditedModule;
    MaxBalanceModule public maxBalanceModule;
    TransferLimitModule public transferLimitModule;

    address public owner;
    address public compliance;
    address public investor1;
    address public investor2;
    address public unverified;

    MockIdentity public identity1;
    MockIdentity public identity2;

    uint256 public constant MAX_BALANCE = 1_000_000e18;
    uint256 public constant DAILY_LIMIT = 100_000e18;

    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    function setUp() public {
        owner = makeAddr("owner");
        compliance = makeAddr("compliance");
        investor1 = makeAddr("investor1");
        investor2 = makeAddr("investor2");
        unverified = makeAddr("unverified");

        // Deploy identity registry
        vm.prank(owner);
        identityRegistry = new IdentityRegistry();

        // Deploy modules
        accreditedModule = new AccreditedInvestorModule(address(identityRegistry));
        maxBalanceModule = new MaxBalanceModule(address(identityRegistry), MAX_BALANCE);
        transferLimitModule = new TransferLimitModule(address(identityRegistry), DAILY_LIMIT);

        // Register identities
        identity1 = new MockIdentity(investor1);
        identity2 = new MockIdentity(investor2);

        vm.startPrank(owner);
        identityRegistry.grantRole(AGENT_ROLE, owner);
        identityRegistry.registerIdentity(investor1, identity1, 840);
        identityRegistry.registerIdentity(investor2, identity2, 840);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                  ACCREDITED INVESTOR MODULE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_AccreditedModule_Name() public view {
        assertEq(accreditedModule.name(), "AccreditedInvestorModule");
    }

    function test_AccreditedModule_AllowsVerifiedInvestor() public {
        vm.prank(compliance);
        accreditedModule.bindCompliance(compliance);

        bool result = accreditedModule.moduleCheck(investor1, investor2, 1000e18, compliance);
        assertTrue(result);
    }

    function test_AccreditedModule_RejectsUnverifiedInvestor() public {
        vm.prank(compliance);
        accreditedModule.bindCompliance(compliance);

        bool result = accreditedModule.moduleCheck(investor1, unverified, 1000e18, compliance);
        assertFalse(result);
    }

    function test_AccreditedModule_IsAccredited() public view {
        assertTrue(accreditedModule.isAccredited(investor1));
        assertFalse(accreditedModule.isAccredited(unverified));
    }

    function test_AccreditedModule_BindCompliance() public {
        vm.prank(compliance);
        accreditedModule.bindCompliance(compliance);

        assertTrue(accreditedModule.isComplianceBound(compliance));
    }

    function test_AccreditedModule_BindCompliance_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit IModule.ComplianceBound(compliance);

        vm.prank(compliance);
        accreditedModule.bindCompliance(compliance);
    }

    function test_AccreditedModule_UnbindCompliance() public {
        vm.startPrank(compliance);
        accreditedModule.bindCompliance(compliance);
        accreditedModule.unbindCompliance(compliance);
        vm.stopPrank();

        assertFalse(accreditedModule.isComplianceBound(compliance));
    }

    /*//////////////////////////////////////////////////////////////
                      MAX BALANCE MODULE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MaxBalanceModule_Name() public view {
        assertEq(maxBalanceModule.name(), "MaxBalanceModule");
    }

    function test_MaxBalanceModule_AllowsTransferWithinLimit() public {
        vm.prank(compliance);
        maxBalanceModule.bindCompliance(compliance);

        bool result = maxBalanceModule.moduleCheck(investor1, investor2, 500_000e18, compliance);
        assertTrue(result);
    }

    function test_MaxBalanceModule_RejectsTransferExceedingLimit() public {
        vm.prank(compliance);
        maxBalanceModule.bindCompliance(compliance);

        bool result = maxBalanceModule.moduleCheck(investor1, investor2, 1_500_000e18, compliance);
        assertFalse(result);
    }

    function test_MaxBalanceModule_RejectsSingleTransferExceedingMax() public {
        vm.prank(compliance);
        maxBalanceModule.bindCompliance(compliance);

        // Even if receiver has no balance, single transfer can't exceed max
        bool result = maxBalanceModule.moduleCheck(investor1, investor2, 2_000_000e18, compliance);
        assertFalse(result);
    }

    function test_MaxBalanceModule_UpdatesBalanceOnTransfer() public {
        vm.prank(compliance);
        maxBalanceModule.bindCompliance(compliance);

        // Mint to investor1
        vm.prank(compliance);
        maxBalanceModule.moduleMintAction(investor1, 1_000_000e18);

        assertEq(maxBalanceModule.getWalletBalance(investor1), 1_000_000e18);

        // Transfer to investor2
        vm.prank(compliance);
        maxBalanceModule.moduleTransferAction(investor1, investor2, 400_000e18);

        assertEq(maxBalanceModule.getWalletBalance(investor1), 600_000e18);
        assertEq(maxBalanceModule.getWalletBalance(investor2), 400_000e18);
    }

    function test_MaxBalanceModule_UpdatesBalanceOnMint() public {
        vm.prank(compliance);
        maxBalanceModule.bindCompliance(compliance);

        vm.prank(compliance);
        maxBalanceModule.moduleMintAction(investor1, 500_000e18);

        assertEq(maxBalanceModule.getWalletBalance(investor1), 500_000e18);
    }

    function test_MaxBalanceModule_UpdatesBalanceOnBurn() public {
        vm.prank(compliance);
        maxBalanceModule.bindCompliance(compliance);

        // Mint first
        vm.prank(compliance);
        maxBalanceModule.moduleMintAction(investor1, 1_000_000e18);

        // Then burn
        vm.prank(compliance);
        maxBalanceModule.moduleBurnAction(investor1, 300_000e18);

        assertEq(maxBalanceModule.getWalletBalance(investor1), 700_000e18);
    }

    function test_MaxBalanceModule_RevertsIfExceedsMaxOnTransfer() public {
        vm.prank(compliance);
        maxBalanceModule.bindCompliance(compliance);

        // Mint to investor1
        vm.prank(compliance);
        maxBalanceModule.moduleMintAction(investor1, 1_000_000e18);

        // Try to transfer more than max (should revert in action, not check)
        vm.expectRevert("MaxBalanceModule: balance exceeds maximum");
        vm.prank(compliance);
        maxBalanceModule.moduleTransferAction(investor1, investor2, 1_000_001e18);
    }

    function test_MaxBalanceModule_SetMaxBalance() public {
        uint256 newMax = 2_000_000e18;

        vm.prank(owner);
        maxBalanceModule.setMaxBalance(newMax);

        assertEq(maxBalanceModule.maxBalance(), newMax);
    }

    function test_MaxBalanceModule_SetMaxBalance_RevertsIfNotOwner() public {
        vm.expectRevert();
        vm.prank(investor1);
        maxBalanceModule.setMaxBalance(2_000_000e18);
    }

    function test_MaxBalanceModule_SetMaxBalance_RevertsIfZero() public {
        vm.expectRevert("MaxBalanceModule: max balance must be positive");
        vm.prank(owner);
        maxBalanceModule.setMaxBalance(0);
    }

    /*//////////////////////////////////////////////////////////////
                    TRANSFER LIMIT MODULE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TransferLimitModule_Name() public view {
        assertEq(transferLimitModule.name(), "TransferLimitModule");
    }

    function test_TransferLimitModule_AllowsTransferWithinLimit() public {
        vm.prank(compliance);
        transferLimitModule.bindCompliance(compliance);

        bool result = transferLimitModule.moduleCheck(investor1, investor2, 50_000e18, compliance);
        assertTrue(result);
    }

    function test_TransferLimitModule_RejectsTransferExceedingLimit() public {
        vm.prank(compliance);
        transferLimitModule.bindCompliance(compliance);

        bool result = transferLimitModule.moduleCheck(investor1, investor2, 150_000e18, compliance);
        assertFalse(result);
    }

    function test_TransferLimitModule_UpdatesDailyVolume() public {
        vm.prank(compliance);
        transferLimitModule.bindCompliance(compliance);

        // First transfer
        vm.prank(compliance);
        transferLimitModule.moduleTransferAction(investor1, investor2, 30_000e18);

        assertEq(transferLimitModule.getTodayVolume(investor1), 30_000e18);

        // Second transfer
        vm.prank(compliance);
        transferLimitModule.moduleTransferAction(investor1, investor2, 20_000e18);

        assertEq(transferLimitModule.getTodayVolume(investor1), 50_000e18);
    }

    function test_TransferLimitModule_RejectsExceedingDailyLimit() public {
        vm.prank(compliance);
        transferLimitModule.bindCompliance(compliance);

        // Transfer 80K
        vm.prank(compliance);
        transferLimitModule.moduleTransferAction(investor1, investor2, 80_000e18);

        // Try to transfer another 30K (would be 110K total)
        bool result = transferLimitModule.moduleCheck(investor1, investor2, 30_000e18, compliance);
        assertFalse(result);
    }

    function test_TransferLimitModule_ResetsNextDay() public {
        vm.prank(compliance);
        transferLimitModule.bindCompliance(compliance);

        // Transfer 100K today
        vm.prank(compliance);
        transferLimitModule.moduleTransferAction(investor1, investor2, 100_000e18);

        assertEq(transferLimitModule.getTodayVolume(investor1), 100_000e18);

        // Warp to next day
        vm.warp(block.timestamp + 1 days);

        // Volume should be 0 for new day
        assertEq(transferLimitModule.getTodayVolume(investor1), 0);

        // Can transfer again
        bool result = transferLimitModule.moduleCheck(investor1, investor2, 100_000e18, compliance);
        assertTrue(result);
    }

    function test_TransferLimitModule_GetRemainingDailyLimit() public {
        vm.prank(compliance);
        transferLimitModule.bindCompliance(compliance);

        // Initially, full limit available
        assertEq(transferLimitModule.getRemainingDailyLimit(investor1), DAILY_LIMIT);

        // After transfer, remaining reduced
        vm.prank(compliance);
        transferLimitModule.moduleTransferAction(investor1, investor2, 30_000e18);

        assertEq(transferLimitModule.getRemainingDailyLimit(investor1), 70_000e18);

        // After exceeding limit, remaining is 0
        vm.prank(compliance);
        transferLimitModule.moduleTransferAction(investor1, investor2, 80_000e18);

        assertEq(transferLimitModule.getRemainingDailyLimit(investor1), 0);
    }

    function test_TransferLimitModule_BurnCountsTowardLimit() public {
        vm.prank(compliance);
        transferLimitModule.bindCompliance(compliance);

        // Burn 50K
        vm.prank(compliance);
        transferLimitModule.moduleBurnAction(investor1, 50_000e18);

        assertEq(transferLimitModule.getTodayVolume(investor1), 50_000e18);

        // Can only transfer 50K more
        bool result = transferLimitModule.moduleCheck(investor1, investor2, 60_000e18, compliance);
        assertFalse(result);
    }

    function test_TransferLimitModule_SetDailyLimit() public {
        uint256 newLimit = 200_000e18;

        vm.prank(owner);
        transferLimitModule.setDailyLimit(newLimit);

        assertEq(transferLimitModule.dailyLimit(), newLimit);
    }

    function test_TransferLimitModule_SetDailyLimit_RevertsIfNotOwner() public {
        vm.expectRevert();
        vm.prank(investor1);
        transferLimitModule.setDailyLimit(200_000e18);
    }

    /*//////////////////////////////////////////////////////////////
                      MODULE BINDING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Module_RevertsIfBindingZeroAddress() public {
        vm.expectRevert("AbstractModule: invalid compliance address");
        vm.prank(address(0));
        accreditedModule.bindCompliance(address(0));
    }

    function test_Module_RevertsIfAlreadyBound() public {
        vm.prank(compliance);
        accreditedModule.bindCompliance(compliance);

        vm.expectRevert("AbstractModule: already bound");
        vm.prank(compliance);
        accreditedModule.bindCompliance(compliance);
    }

    function test_Module_RevertsIfUnbindingNotBound() public {
        vm.expectRevert("AbstractModule: not bound");
        vm.prank(compliance);
        accreditedModule.unbindCompliance(compliance);
    }

    function test_Module_RevertsIfActionCalledByNonCompliance() public {
        vm.expectRevert("AbstractModule: caller is not a bound compliance");
        vm.prank(investor1);
        maxBalanceModule.moduleTransferAction(investor1, investor2, 1000e18);
    }

    /*//////////////////////////////////////////////////////////////
                      IDENTITY REGISTRY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Module_SetIdentityRegistry() public {
        address newRegistry = makeAddr("newRegistry");

        vm.prank(owner);
        accreditedModule.setIdentityRegistry(newRegistry);

        assertEq(accreditedModule.getIdentityRegistry(), newRegistry);
    }

    function test_Module_SetIdentityRegistry_RevertsIfNotOwner() public {
        address newRegistry = makeAddr("newRegistry");

        vm.expectRevert();
        vm.prank(investor1);
        accreditedModule.setIdentityRegistry(newRegistry);
    }

    function test_Module_SetIdentityRegistry_RevertsIfZeroAddress() public {
        vm.expectRevert("AbstractModule: invalid identity registry");
        vm.prank(owner);
        accreditedModule.setIdentityRegistry(address(0));
    }
}
