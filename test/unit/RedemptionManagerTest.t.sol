// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {RedemptionManager} from "../../src/redemption/RedemptionManager.sol";
import {IRedemptionManager} from "../../src/redemption/interfaces/IRedemptionManager.sol";
import {StockToken} from "../../src/token/StockToken.sol";
import {IdentityRegistry} from "../../src/identity/IdentityRegistry.sol";
import {ModularCompliance} from "../../src/compliance/ModularCompliance.sol";
import {MockPriceOracle} from "../../src/oracle/mocks/MockPriceOracle.sol";
import {MockIdentity} from "../../src/identity/mocks/MockIdentity.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract RedemptionManagerTest is Test {
    RedemptionManager public redemptionManager;
    StockToken public stockToken;
    IdentityRegistry public identityRegistry;
    ModularCompliance public compliance;
    MockPriceOracle public stockOracle;
    MockPriceOracle public usdcOracle;
    MockERC20 public usdc;

    address public owner;
    address public oracle;
    address public investor1;
    address public investor2;

    MockIdentity public investor1Identity;
    MockIdentity public investor2Identity;

    // Constants
    uint256 public constant MINIMUM_REDEMPTION = 100e18; // $100
    int256 public constant STOCK_PRICE = 250_00000000; // $250 (8 decimals)
    int256 public constant USDC_PRICE = 1_00000000; // $1 (8 decimals)

    function setUp() public {
        owner = address(this);
        oracle = makeAddr("oracle");
        investor1 = makeAddr("investor1");
        investor2 = makeAddr("investor2");

        // Deploy oracles
        stockOracle = new MockPriceOracle(STOCK_PRICE, "STOCK / USD");
        usdcOracle = new MockPriceOracle(USDC_PRICE, "USDC / USD");

        // Deploy USDC mock
        usdc = new MockERC20("USD Coin", "USDC", 6); // USDC has 6 decimals

        // Deploy identity registry
        identityRegistry = new IdentityRegistry();

        // Deploy compliance
        compliance = new ModularCompliance();

        // Deploy stock token
        stockToken = new StockToken("Stock Token", "STOCK", 18, address(identityRegistry), address(compliance));

        // Bind token to compliance (must be done by owner)
        compliance.bindToken(address(stockToken));

        // Deploy redemption manager
        redemptionManager = new RedemptionManager(
            address(stockToken), address(usdc), address(stockOracle), address(usdcOracle), MINIMUM_REDEMPTION
        );

        // Grant oracle role
        redemptionManager.grantRole(redemptionManager.ORACLE_ROLE(), oracle);

        // Setup identities
        investor1Identity = new MockIdentity(investor1);
        investor2Identity = new MockIdentity(investor2);

        vm.startPrank(owner);
        identityRegistry.grantRole(identityRegistry.AGENT_ROLE(), owner);
        identityRegistry.registerIdentity(investor1, investor1Identity, 840);
        identityRegistry.registerIdentity(investor2, investor2Identity, 840);
        vm.stopPrank();

        // Grant agent role to owner for minting
        stockToken.grantRole(stockToken.AGENT_ROLE(), owner);

        // Grant redemption manager permission to burn
        stockToken.grantRole(stockToken.AGENT_ROLE(), address(redemptionManager));

        // Unpause token
        stockToken.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                           DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment() public view {
        assertEq(address(redemptionManager.i_stockToken()), address(stockToken));
        assertEq(address(redemptionManager.i_usdc()), address(usdc));
        assertEq(redemptionManager.getMinimumRedemption(), MINIMUM_REDEMPTION);
        assertEq(redemptionManager.getRedemptionExpiry(), 7 days);
    }

    function test_Deployment_GrantsRoles() public view {
        assertTrue(redemptionManager.hasRole(redemptionManager.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(redemptionManager.hasRole(redemptionManager.ORACLE_ROLE(), owner));
        assertTrue(redemptionManager.hasRole(redemptionManager.ORACLE_ROLE(), oracle));
    }

    /*//////////////////////////////////////////////////////////////
                      REQUEST REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RequestRedemption() public {
        // Mint tokens to investor1
        stockToken.mint(investor1, 10e18);

        // Request redemption
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);

        // Check request
        (address user, uint256 tokenAmount, uint256 expectedUsdc, uint256 timestamp, bool fulfilled) =
            redemptionManager.getRedemptionRequest(requestId);

        assertEq(user, investor1);
        assertEq(tokenAmount, 10e18);
        assertEq(expectedUsdc, 2500e18); // 10 tokens * $250 = $2500
        assertEq(timestamp, block.timestamp);
        assertFalse(fulfilled);

        // Check tokens were burned
        assertEq(stockToken.balanceOf(investor1), 0);
    }

    function test_RequestRedemption_EmitsEvent() public {
        stockToken.mint(investor1, 10e18);

        vm.expectEmit(false, true, false, true);
        emit IRedemptionManager.RedemptionRequested(bytes32(0), investor1, 10e18, 2500e18);

        vm.prank(investor1);
        redemptionManager.requestRedemption(10e18);
    }

    function test_RequestRedemption_RevertsIfBelowMinimum() public {
        // Mint small amount
        stockToken.mint(investor1, 0.1e18); // 0.1 tokens = $25 < $100 minimum

        vm.expectRevert(IRedemptionManager.RedemptionManager__BelowMinimum.selector);
        vm.prank(investor1);
        redemptionManager.requestRedemption(0.1e18);
    }

    function test_RequestRedemption_RevertsIfInsufficientBalance() public {
        stockToken.mint(investor1, 5e18);

        vm.expectRevert(IRedemptionManager.RedemptionManager__InsufficientBalance.selector);
        vm.prank(investor1);
        redemptionManager.requestRedemption(10e18); // Trying to redeem more than balance
    }

    function test_RequestRedemption_MultipleRequests() public {
        stockToken.mint(investor1, 100e18);

        vm.startPrank(investor1);
        bytes32 requestId1 = redemptionManager.requestRedemption(10e18);
        bytes32 requestId2 = redemptionManager.requestRedemption(20e18);
        vm.stopPrank();

        // Check both requests exist
        (address user1,,,,) = redemptionManager.getRedemptionRequest(requestId1);
        (address user2,,,,) = redemptionManager.getRedemptionRequest(requestId2);

        assertEq(user1, investor1);
        assertEq(user2, investor1);
        assertEq(stockToken.balanceOf(investor1), 70e18);
    }

    /*//////////////////////////////////////////////////////////////
                      FINALIZE REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FinalizeRedemption() public {
        // Setup: Request redemption
        stockToken.mint(investor1, 10e18);
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);

        // Oracle sends USDC to contract
        usdc.mint(address(redemptionManager), 2500e6); // USDC has 6 decimals

        // Oracle finalizes
        vm.prank(oracle);
        redemptionManager.finalizeRedemption(requestId, 2500e18);

        // Check request is fulfilled
        (,,,, bool fulfilled) = redemptionManager.getRedemptionRequest(requestId);
        assertTrue(fulfilled);

        // Check withdrawal balance
        assertEq(redemptionManager.getWithdrawalBalance(investor1), 2500e18);
    }

    function test_FinalizeRedemption_EmitsEvent() public {
        stockToken.mint(investor1, 10e18);
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);

        usdc.mint(address(redemptionManager), 2500e6);

        vm.expectEmit(true, true, false, true);
        emit IRedemptionManager.RedemptionFulfilled(requestId, investor1, 2500e18);

        vm.prank(oracle);
        redemptionManager.finalizeRedemption(requestId, 2500e18);
    }

    function test_FinalizeRedemption_RevertsIfNotOracle() public {
        stockToken.mint(investor1, 10e18);
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);

        vm.expectRevert();
        vm.prank(investor1);
        redemptionManager.finalizeRedemption(requestId, 2500e18);
    }

    function test_FinalizeRedemption_RevertsIfRequestNotFound() public {
        bytes32 fakeRequestId = keccak256("fake");

        vm.expectRevert(IRedemptionManager.RedemptionManager__RequestNotFound.selector);
        vm.prank(oracle);
        redemptionManager.finalizeRedemption(fakeRequestId, 2500e18);
    }

    function test_FinalizeRedemption_RevertsIfAlreadyFulfilled() public {
        stockToken.mint(investor1, 10e18);
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);

        usdc.mint(address(redemptionManager), 5000e6);

        vm.startPrank(oracle);
        redemptionManager.finalizeRedemption(requestId, 2500e18);

        vm.expectRevert(IRedemptionManager.RedemptionManager__RequestAlreadyFulfilled.selector);
        redemptionManager.finalizeRedemption(requestId, 2500e18);
        vm.stopPrank();
    }

    function test_FinalizeRedemption_RevertsIfSlippageExceeded() public {
        stockToken.mint(investor1, 10e18);
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);

        // Expected: 2500 USDC
        // Min acceptable (2% slippage): 2450 USDC
        // Trying to finalize with 2400 USDC (too low)

        vm.expectRevert(IRedemptionManager.RedemptionManager__SlippageExceeded.selector);
        vm.prank(oracle);
        redemptionManager.finalizeRedemption(requestId, 2400e18);
    }

    function test_FinalizeRedemption_AllowsSlippageWithinTolerance() public {
        stockToken.mint(investor1, 10e18);
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);

        usdc.mint(address(redemptionManager), 2450e6);

        // Expected: 2500 USDC
        // Min acceptable (2% slippage): 2450 USDC
        // Finalizing with exactly 2450 USDC (should work)

        vm.prank(oracle);
        redemptionManager.finalizeRedemption(requestId, 2450e18);

        assertEq(redemptionManager.getWithdrawalBalance(investor1), 2450e18);
    }

    /*//////////////////////////////////////////////////////////////
                          WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Withdraw() public {
        // Setup: Request and finalize redemption
        stockToken.mint(investor1, 10e18);
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);

        usdc.mint(address(redemptionManager), 2500e6);
        vm.prank(oracle);
        redemptionManager.finalizeRedemption(requestId, 2500e18);

        // Withdraw
        vm.prank(investor1);
        uint256 amount = redemptionManager.withdraw();

        assertEq(amount, 2500e18);
        assertEq(usdc.balanceOf(investor1), 2500e6); // USDC has 6 decimals
        assertEq(redemptionManager.getWithdrawalBalance(investor1), 0);
    }

    function test_Withdraw_EmitsEvent() public {
        stockToken.mint(investor1, 10e18);
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);

        usdc.mint(address(redemptionManager), 2500e6);
        vm.prank(oracle);
        redemptionManager.finalizeRedemption(requestId, 2500e18);

        vm.expectEmit(true, false, false, true);
        emit IRedemptionManager.Withdrawn(investor1, 2500e18);

        vm.prank(investor1);
        redemptionManager.withdraw();
    }

    function test_Withdraw_RevertsIfNoBalance() public {
        vm.expectRevert(IRedemptionManager.RedemptionManager__NoWithdrawalBalance.selector);
        vm.prank(investor1);
        redemptionManager.withdraw();
    }

    function test_Withdraw_MultipleRedemptions() public {
        // Setup: Multiple redemptions
        stockToken.mint(investor1, 100e18);

        vm.startPrank(investor1);
        bytes32 requestId1 = redemptionManager.requestRedemption(10e18);
        bytes32 requestId2 = redemptionManager.requestRedemption(20e18);
        vm.stopPrank();

        // Finalize both
        usdc.mint(address(redemptionManager), 10000e6);
        vm.startPrank(oracle);
        redemptionManager.finalizeRedemption(requestId1, 2500e18);
        redemptionManager.finalizeRedemption(requestId2, 5000e18);
        vm.stopPrank();

        // Withdraw all at once
        vm.prank(investor1);
        uint256 amount = redemptionManager.withdraw();

        assertEq(amount, 7500e18); // 2500 + 5000
        assertEq(usdc.balanceOf(investor1), 7500e6);
    }

    /*//////////////////////////////////////////////////////////////
                      CANCEL REDEMPTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CancelRedemption() public {
        // Setup: Request redemption
        stockToken.mint(investor1, 10e18);
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);

        // Warp past expiry
        vm.warp(block.timestamp + 7 days + 1);

        // Cancel
        vm.prank(investor1);
        redemptionManager.cancelRedemption(requestId);

        // Check request is marked fulfilled
        (,,,, bool fulfilled) = redemptionManager.getRedemptionRequest(requestId);
        assertTrue(fulfilled);

        // Check tokens were refunded
        assertEq(stockToken.balanceOf(investor1), 10e18);
    }

    function test_CancelRedemption_EmitsEvent() public {
        stockToken.mint(investor1, 10e18);
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);

        vm.warp(block.timestamp + 7 days + 1);

        vm.expectEmit(true, true, false, false);
        emit IRedemptionManager.RedemptionCancelled(requestId, investor1);

        vm.prank(investor1);
        redemptionManager.cancelRedemption(requestId);
    }

    function test_CancelRedemption_RevertsIfNotExpired() public {
        stockToken.mint(investor1, 10e18);
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);

        vm.expectRevert(IRedemptionManager.RedemptionManager__RequestNotExpired.selector);
        vm.prank(investor1);
        redemptionManager.cancelRedemption(requestId);
    }

    function test_CancelRedemption_RevertsIfAlreadyFulfilled() public {
        stockToken.mint(investor1, 10e18);
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);

        usdc.mint(address(redemptionManager), 2500e6);
        vm.prank(oracle);
        redemptionManager.finalizeRedemption(requestId, 2500e18);

        vm.warp(block.timestamp + 7 days + 1);

        vm.expectRevert(IRedemptionManager.RedemptionManager__RequestAlreadyFulfilled.selector);
        vm.prank(investor1);
        redemptionManager.cancelRedemption(requestId);
    }

    function test_CancelRedemption_RevertsIfWrongUser() public {
        stockToken.mint(investor1, 10e18);
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);

        vm.warp(block.timestamp + 7 days + 1);

        vm.expectRevert(IRedemptionManager.RedemptionManager__RequestNotFound.selector);
        vm.prank(investor2);
        redemptionManager.cancelRedemption(requestId);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsRequestExpired() public {
        stockToken.mint(investor1, 10e18);
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);

        assertFalse(redemptionManager.isRequestExpired(requestId));

        vm.warp(block.timestamp + 7 days + 1);

        assertTrue(redemptionManager.isRequestExpired(requestId));
    }

    /*//////////////////////////////////////////////////////////////
                          INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CompleteRedemptionFlow() public {
        // 1. Mint tokens
        stockToken.mint(investor1, 100e18);
        assertEq(stockToken.balanceOf(investor1), 100e18);

        // 2. Request redemption
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(10e18);
        assertEq(stockToken.balanceOf(investor1), 90e18); // Burned

        // 3. Oracle processes off-chain (simulated)
        usdc.mint(address(redemptionManager), 2500e6);

        // 4. Oracle finalizes
        vm.prank(oracle);
        redemptionManager.finalizeRedemption(requestId, 2500e18);
        assertEq(redemptionManager.getWithdrawalBalance(investor1), 2500e18);

        // 5. User withdraws
        vm.prank(investor1);
        redemptionManager.withdraw();
        assertEq(usdc.balanceOf(investor1), 2500e6);
        assertEq(redemptionManager.getWithdrawalBalance(investor1), 0);
    }

    function test_MultipleUsersRedemption() public {
        // Setup
        stockToken.mint(investor1, 50e18);
        stockToken.mint(investor2, 50e18);

        // Both request redemption
        vm.prank(investor1);
        bytes32 requestId1 = redemptionManager.requestRedemption(10e18);

        vm.prank(investor2);
        bytes32 requestId2 = redemptionManager.requestRedemption(20e18);

        // Oracle finalizes both
        usdc.mint(address(redemptionManager), 10000e6);
        vm.startPrank(oracle);
        redemptionManager.finalizeRedemption(requestId1, 2500e18);
        redemptionManager.finalizeRedemption(requestId2, 5000e18);
        vm.stopPrank();

        // Both withdraw
        vm.prank(investor1);
        redemptionManager.withdraw();
        assertEq(usdc.balanceOf(investor1), 2500e6);

        vm.prank(investor2);
        redemptionManager.withdraw();
        assertEq(usdc.balanceOf(investor2), 5000e6);
    }
}
