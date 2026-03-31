// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {StockToken} from "../../src/token/StockToken.sol";
import {IStockToken} from "../../src/token/interfaces/IStockToken.sol";
import {IdentityRegistry} from "../../src/identity/IdentityRegistry.sol";
import {MockIdentity} from "../../src/identity/mocks/MockIdentity.sol";
import {ModularCompliance} from "../../src/compliance/ModularCompliance.sol";
import {MaxBalanceModule} from "../../src/compliance/modules/MaxBalanceModule.sol";
import {TransferLimitModule} from "../../src/compliance/modules/TransferLimitModule.sol";

/**
 * @title StockTokenTest
 * @notice Comprehensive tests for StockToken contract
 */
contract StockTokenTest is Test {
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    StockToken public token;
    IdentityRegistry public identityRegistry;
    ModularCompliance public compliance;
    MaxBalanceModule public maxBalanceModule;

    address public owner;
    address public agent;
    address public investor1;
    address public investor2;
    address public investor3;
    address public unverified;

    MockIdentity public identity1;
    MockIdentity public identity2;
    MockIdentity public identity3;

    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    uint256 public constant MAX_BALANCE = 1_000_000e18;
    uint256 public constant INITIAL_SUPPLY = 10_000_000e18;

    function setUp() public {
        owner = makeAddr("owner");
        agent = makeAddr("agent");
        investor1 = makeAddr("investor1");
        investor2 = makeAddr("investor2");
        investor3 = makeAddr("investor3");
        unverified = makeAddr("unverified");

        // Deploy identity registry
        vm.prank(owner);
        identityRegistry = new IdentityRegistry();

        // Deploy compliance
        vm.prank(owner);
        compliance = new ModularCompliance();

        // Deploy token
        vm.prank(owner);
        token = new StockToken(
            "Tokenized TSLA Stock",
            "dTSLA",
            18,
            address(identityRegistry),
            address(compliance)
        );

        // Grant agent role
        vm.prank(owner);
        token.grantRole(AGENT_ROLE, agent);

        // Register identities
        identity1 = new MockIdentity(investor1);
        identity2 = new MockIdentity(investor2);
        identity3 = new MockIdentity(investor3);

        vm.startPrank(owner);
        identityRegistry.grantRole(AGENT_ROLE, owner);
        identityRegistry.registerIdentity(investor1, identity1, 840);
        identityRegistry.registerIdentity(investor2, identity2, 840);
        identityRegistry.registerIdentity(investor3, identity3, 840);
        vm.stopPrank();

        // Unpause token
        vm.prank(agent);
        token.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                          DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment() public view {
        assertEq(token.name(), "Tokenized TSLA Stock");
        assertEq(token.symbol(), "dTSLA");
        assertEq(token.decimals(), 18);
        assertEq(address(token.identityRegistry()), address(identityRegistry));
        assertEq(address(token.compliance()), address(compliance));
        assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertTrue(token.hasRole(AGENT_ROLE, owner));
    }

    function test_Deployment_StartsUnpaused() public view {
        // Token is unpaused in setUp
        assertFalse(token.paused());
    }

    /*//////////////////////////////////////////////////////////////
                          MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Mint() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        assertEq(token.balanceOf(investor1), 1000e18);
        assertEq(token.totalSupply(), 1000e18);
    }

    function test_Mint_EmitsTransferEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IStockToken.Transfer(address(0), investor1, 1000e18);

        vm.prank(agent);
        token.mint(investor1, 1000e18);
    }

    function test_Mint_RevertsIfNotAgent() public {
        vm.expectRevert();
        vm.prank(investor1);
        token.mint(investor1, 1000e18);
    }

    function test_Mint_RevertsIfReceiverNotVerified() public {
        vm.expectRevert("StockToken: receiver not verified");
        vm.prank(agent);
        token.mint(unverified, 1000e18);
    }

    function test_Mint_RevertsIfZeroAddress() public {
        vm.expectRevert("StockToken: mint to zero address");
        vm.prank(agent);
        token.mint(address(0), 1000e18);
    }

    function test_BatchMint() public {
        address[] memory toList = new address[](2);
        toList[0] = investor1;
        toList[1] = investor2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000e18;
        amounts[1] = 2000e18;

        vm.prank(agent);
        token.batchMint(toList, amounts);

        assertEq(token.balanceOf(investor1), 1000e18);
        assertEq(token.balanceOf(investor2), 2000e18);
    }

    /*//////////////////////////////////////////////////////////////
                          TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Transfer() public {
        // Mint to investor1
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        // Transfer to investor2
        vm.prank(investor1);
        token.transfer(investor2, 400e18);

        assertEq(token.balanceOf(investor1), 600e18);
        assertEq(token.balanceOf(investor2), 400e18);
    }

    function test_Transfer_EmitsEvent() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.expectEmit(true, true, false, true);
        emit IStockToken.Transfer(investor1, investor2, 400e18);

        vm.prank(investor1);
        token.transfer(investor2, 400e18);
    }

    function test_Transfer_RevertsIfPaused() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.prank(agent);
        token.pause();

        vm.expectRevert("StockToken: token is paused");
        vm.prank(investor1);
        token.transfer(investor2, 400e18);
    }

    function test_Transfer_RevertsIfSenderFrozen() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.prank(agent);
        token.setAddressFrozen(investor1, true);

        vm.expectRevert("StockToken: address is frozen");
        vm.prank(investor1);
        token.transfer(investor2, 400e18);
    }

    function test_Transfer_RevertsIfReceiverFrozen() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.prank(agent);
        token.setAddressFrozen(investor2, true);

        vm.expectRevert("StockToken: address is frozen");
        vm.prank(investor1);
        token.transfer(investor2, 400e18);
    }

    function test_Transfer_RevertsIfReceiverNotVerified() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.expectRevert("StockToken: receiver not verified");
        vm.prank(investor1);
        token.transfer(unverified, 400e18);
    }

    function test_Transfer_RevertsIfInsufficientBalance() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.expectRevert();
        vm.prank(investor1);
        token.transfer(investor2, 2000e18);
    }

    function test_Transfer_WithComplianceModule() public {
        // Add max balance module
        maxBalanceModule = new MaxBalanceModule(address(identityRegistry), MAX_BALANCE);
        vm.prank(owner);
        compliance.addModule(address(maxBalanceModule));

        // Mint within limit
        vm.prank(agent);
        token.mint(investor1, 500_000e18);

        // Transfer within limit
        vm.prank(investor1);
        token.transfer(investor2, 400_000e18);

        assertEq(token.balanceOf(investor2), 400_000e18);
    }

    function test_Transfer_RevertsIfComplianceRejects() public {
        // Add max balance module
        maxBalanceModule = new MaxBalanceModule(address(identityRegistry), MAX_BALANCE);
        vm.prank(owner);
        compliance.addModule(address(maxBalanceModule));

        // Mint to investor1
        vm.prank(agent);
        token.mint(investor1, 1_500_000e18);

        // Try to transfer more than max balance
        vm.expectRevert("StockToken: transfer not compliant");
        vm.prank(investor1);
        token.transfer(investor2, 1_100_000e18);
    }

    function test_TransferFrom() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        // Approve investor2
        vm.prank(investor1);
        token.approve(investor2, 400e18);

        // Transfer from investor1 to investor3
        vm.prank(investor2);
        token.transferFrom(investor1, investor3, 400e18);

        assertEq(token.balanceOf(investor1), 600e18);
        assertEq(token.balanceOf(investor3), 400e18);
        assertEq(token.allowance(investor1, investor2), 0);
    }

    function test_BatchTransfer() public {
        vm.prank(agent);
        token.mint(investor1, 3000e18);

        address[] memory toList = new address[](2);
        toList[0] = investor2;
        toList[1] = investor3;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000e18;
        amounts[1] = 500e18;

        vm.prank(investor1);
        token.batchTransfer(toList, amounts);

        assertEq(token.balanceOf(investor1), 1500e18);
        assertEq(token.balanceOf(investor2), 1000e18);
        assertEq(token.balanceOf(investor3), 500e18);
    }

    /*//////////////////////////////////////////////////////////////
                          BURN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Burn() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.prank(agent);
        token.burn(investor1, 400e18);

        assertEq(token.balanceOf(investor1), 600e18);
        assertEq(token.totalSupply(), 600e18);
    }

    function test_Burn_RevertsIfNotAgent() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.expectRevert();
        vm.prank(investor1);
        token.burn(investor1, 400e18);
    }

    function test_Burn_RevertsIfInsufficientBalance() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.expectRevert("StockToken: burn amount exceeds balance");
        vm.prank(agent);
        token.burn(investor1, 2000e18);
    }

    function test_Burn_UnfreezesFrozenTokensIfNeeded() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        // Freeze 600 tokens
        vm.prank(agent);
        token.freezePartialTokens(investor1, 600e18);

        // Burn 800 tokens (should unfreeze 400)
        vm.prank(agent);
        token.burn(investor1, 800e18);

        assertEq(token.balanceOf(investor1), 200e18);
        assertEq(token.getFrozenTokens(investor1), 200e18);
    }

    function test_BatchBurn() public {
        vm.startPrank(agent);
        token.mint(investor1, 1000e18);
        token.mint(investor2, 2000e18);
        vm.stopPrank();

        address[] memory fromList = new address[](2);
        fromList[0] = investor1;
        fromList[1] = investor2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 400e18;
        amounts[1] = 800e18;

        vm.prank(agent);
        token.batchBurn(fromList, amounts);

        assertEq(token.balanceOf(investor1), 600e18);
        assertEq(token.balanceOf(investor2), 1200e18);
    }

    /*//////////////////////////////////////////////////////////////
                          FREEZING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetAddressFrozen() public {
        vm.prank(agent);
        token.setAddressFrozen(investor1, true);

        assertTrue(token.isFrozen(investor1));
    }

    function test_SetAddressFrozen_EmitsEvent() public {
        vm.expectEmit(true, false, true, true);
        emit IStockToken.AddressFrozen(investor1, true, agent);

        vm.prank(agent);
        token.setAddressFrozen(investor1, true);
    }

    function test_SetAddressFrozen_RevertsIfNotAgent() public {
        vm.expectRevert();
        vm.prank(investor1);
        token.setAddressFrozen(investor1, true);
    }

    function test_FreezePartialTokens() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.prank(agent);
        token.freezePartialTokens(investor1, 600e18);

        assertEq(token.getFrozenTokens(investor1), 600e18);
    }

    function test_FreezePartialTokens_EmitsEvent() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.expectEmit(true, false, false, true);
        emit IStockToken.TokensFrozen(investor1, 600e18);

        vm.prank(agent);
        token.freezePartialTokens(investor1, 600e18);
    }

    function test_FreezePartialTokens_RevertsIfExceedsBalance() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.expectRevert("StockToken: amount exceeds available balance");
        vm.prank(agent);
        token.freezePartialTokens(investor1, 1500e18);
    }

    function test_Transfer_RevertsIfInsufficientUnfrozenBalance() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.prank(agent);
        token.freezePartialTokens(investor1, 700e18);

        // Can only transfer 300 unfrozen tokens
        vm.expectRevert("StockToken: insufficient unfrozen balance");
        vm.prank(investor1);
        token.transfer(investor2, 400e18);
    }

    function test_UnfreezePartialTokens() public {
        vm.startPrank(agent);
        token.mint(investor1, 1000e18);
        token.freezePartialTokens(investor1, 600e18);
        token.unfreezePartialTokens(investor1, 200e18);
        vm.stopPrank();

        assertEq(token.getFrozenTokens(investor1), 400e18);
    }

    /*//////////////////////////////////////////////////////////////
                      FORCED TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ForcedTransfer() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.prank(agent);
        token.forcedTransfer(investor1, investor2, 400e18);

        assertEq(token.balanceOf(investor1), 600e18);
        assertEq(token.balanceOf(investor2), 400e18);
    }

    function test_ForcedTransfer_RevertsIfNotAgent() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.expectRevert();
        vm.prank(investor1);
        token.forcedTransfer(investor1, investor2, 400e18);
    }

    function test_ForcedTransfer_UnfreezesFrozenTokens() public {
        vm.startPrank(agent);
        token.mint(investor1, 1000e18);
        token.freezePartialTokens(investor1, 700e18);
        token.forcedTransfer(investor1, investor2, 800e18);
        vm.stopPrank();

        assertEq(token.balanceOf(investor1), 200e18);
        assertEq(token.balanceOf(investor2), 800e18);
        assertEq(token.getFrozenTokens(investor1), 0);
    }

    function test_ForcedTransfer_RevertsIfReceiverNotVerified() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.expectRevert("StockToken: receiver not verified");
        vm.prank(agent);
        token.forcedTransfer(investor1, unverified, 400e18);
    }

    /*//////////////////////////////////////////////////////////////
                      REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RequestRedemption() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.expectEmit(true, false, false, true);
        emit IStockToken.RedemptionRequested(investor1, 400e18);

        vm.prank(investor1);
        token.requestRedemption(400e18);

        // Tokens should be burned
        assertEq(token.balanceOf(investor1), 600e18);
        assertEq(token.totalSupply(), 600e18);
    }

    function test_RequestRedemption_RevertsIfPaused() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.prank(agent);
        token.pause();

        vm.expectRevert("StockToken: token is paused");
        vm.prank(investor1);
        token.requestRedemption(400e18);
    }

    function test_RequestRedemption_RevertsIfFrozen() public {
        vm.prank(agent);
        token.mint(investor1, 1000e18);

        vm.prank(agent);
        token.setAddressFrozen(investor1, true);

        vm.expectRevert("StockToken: address is frozen");
        vm.prank(investor1);
        token.requestRedemption(400e18);
    }

    function test_RequestRedemption_RevertsIfZeroAmount() public {
        vm.expectRevert("StockToken: amount must be positive");
        vm.prank(investor1);
        token.requestRedemption(0);
    }

    /*//////////////////////////////////////////////////////////////
                      PAUSE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Pause() public {
        vm.prank(agent);
        token.pause();

        assertTrue(token.paused());
    }

    function test_Pause_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit IStockToken.Paused(agent);

        vm.prank(agent);
        token.pause();
    }

    function test_Pause_RevertsIfNotAgent() public {
        vm.expectRevert();
        vm.prank(investor1);
        token.pause();
    }

    function test_Unpause() public {
        vm.startPrank(agent);
        token.pause();
        token.unpause();
        vm.stopPrank();

        assertFalse(token.paused());
    }

    /*//////////////////////////////////////////////////////////////
                      ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetIdentityRegistry() public {
        IdentityRegistry newRegistry = new IdentityRegistry();

        vm.prank(owner);
        token.setIdentityRegistry(address(newRegistry));

        assertEq(address(token.identityRegistry()), address(newRegistry));
    }

    function test_SetIdentityRegistry_RevertsIfNotOwner() public {
        IdentityRegistry newRegistry = new IdentityRegistry();

        vm.expectRevert();
        vm.prank(agent);
        token.setIdentityRegistry(address(newRegistry));
    }

    function test_SetCompliance() public {
        ModularCompliance newCompliance = new ModularCompliance();

        vm.prank(owner);
        token.setCompliance(address(newCompliance));

        assertEq(address(token.compliance()), address(newCompliance));
    }

    /*//////////////////////////////////////////////////////////////
                      INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CompleteTokenLifecycle() public {
        // 1. Mint to investor1
        vm.prank(agent);
        token.mint(investor1, 10_000e18);

        // 2. Transfer to investor2
        vm.prank(investor1);
        token.transfer(investor2, 3_000e18);

        // 3. Investor2 requests redemption
        vm.prank(investor2);
        token.requestRedemption(1_000e18);

        // 4. Verify final balances
        assertEq(token.balanceOf(investor1), 7_000e18);
        assertEq(token.balanceOf(investor2), 2_000e18);
        assertEq(token.totalSupply(), 9_000e18);
    }

    function test_MultipleInvestorsWithCompliance() public {
        // Add max balance module
        maxBalanceModule = new MaxBalanceModule(address(identityRegistry), MAX_BALANCE);
        vm.prank(owner);
        compliance.addModule(address(maxBalanceModule));

        // Mint to multiple investors
        vm.startPrank(agent);
        token.mint(investor1, 500_000e18);
        token.mint(investor2, 700_000e18);
        token.mint(investor3, 300_000e18);
        vm.stopPrank();

        // Transfers should respect compliance
        vm.prank(investor1);
        token.transfer(investor2, 100_000e18);

        // investor2 now has 800K, cannot receive more than 200K
        vm.expectRevert("StockToken: transfer not compliant");
        vm.prank(investor3);
        token.transfer(investor2, 250_000e18);
    }
}
