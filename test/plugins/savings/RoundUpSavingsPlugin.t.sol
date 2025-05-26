// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {RoundUpSavingsPlugin} from "../../../contracts/plugins/savings/RoundUpSavingsPlugin.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockPluginExecutor} from "../../mocks/MockPluginExecutor.sol";

contract RoundUpSavingsPluginTest is Test {
    RoundUpSavingsPlugin public plugin;
    MockERC20 public token;
    MockPluginExecutor public executor;
    address public user = address(0x1);
    address public savingsAccount = address(0x2);
    address public recipient = address(0x3);

    function setUp() public {
        plugin = new RoundUpSavingsPlugin();
        token = new MockERC20("Test Token", "TEST", 18);
        executor = new MockPluginExecutor();
        
        // Setup initial balances
        token.mint(user, 1000 ether);
        vm.startPrank(user);
        token.approve(address(executor), type(uint256).max);
        token.approve(address(plugin), type(uint256).max);
        vm.stopPrank();

        // Setup executor as the plugin's executor
        executor.setAccount(user);
        vm.startPrank(address(executor));
        plugin.onInstall("");
        vm.stopPrank();
    }

    function test_CreateAutomation() public {
        vm.startPrank(user);
        plugin.createAutomation(savingsAccount, 10 ether);
        
        (address savedSavingsAccount, uint256 roundUpTo, bool enabled) = plugin.savingsAutomations(user);
        assertEq(savedSavingsAccount, savingsAccount);
        assertEq(roundUpTo, 10 ether);
        assertTrue(enabled);
        vm.stopPrank();
    }

    function test_PauseAutomation() public {
        vm.startPrank(user);
        plugin.createAutomation(savingsAccount, 10 ether);
        plugin.pauseAutomation();
        
        (,, bool enabled) = plugin.savingsAutomations(user);
        assertFalse(enabled);
        vm.stopPrank();
    }

    function test_RoundUpTransfer() public {
        vm.startPrank(user);
        plugin.createAutomation(savingsAccount, 10 ether);
        vm.stopPrank();
        
        // Transfer 7 ETH, should round up to 10 ETH and save 3 ETH
        bytes memory data = abi.encode(
            address(token),
            0,
            abi.encodeWithSelector(IERC20.transfer.selector, recipient, 7 ether)
        );
        
        // First execute the main transfer
        vm.startPrank(user);
        token.transfer(recipient, 7 ether);
        vm.stopPrank();

        // Then execute the plugin hook which should trigger the savings transfer
        vm.startPrank(address(executor));
        plugin.preExecutionHook(0, address(executor), 0, data);
        vm.stopPrank();
        
        assertEq(token.balanceOf(recipient), 7 ether);
        assertEq(token.balanceOf(savingsAccount), 3 ether);
        assertEq(token.balanceOf(user), 990 ether);
    }

    function test_RoundUpTransferWithInsufficientBalance() public {
        vm.startPrank(user);
        plugin.createAutomation(savingsAccount, 10 ether);
        token.burn(user, 991 ether); // Leave only 9 ETH
        vm.stopPrank();
        
        bytes memory data = abi.encode(
            address(token),
            0,
            abi.encodeWithSelector(IERC20.transfer.selector, recipient, 8 ether)
        );
        
        // First execute the main transfer
        vm.startPrank(user);
        token.transfer(recipient, 8 ether);
        vm.stopPrank();

        // Then execute the plugin hook which should trigger the savings transfer
        vm.startPrank(address(executor));
        plugin.preExecutionHook(0, address(executor), 0, data);
        vm.stopPrank();
        
        assertEq(token.balanceOf(recipient), 8 ether);
        assertEq(token.balanceOf(savingsAccount), 1 ether); // Only saves 1 ETH due to insufficient balance
        assertEq(token.balanceOf(user), 0);
    }

    function test_NoRoundUpWhenAutomationDisabled() public {
        vm.startPrank(user);
        plugin.createAutomation(savingsAccount, 10 ether);
        plugin.pauseAutomation();
        vm.stopPrank();
        
        bytes memory data = abi.encode(
            address(token),
            0,
            abi.encodeWithSelector(IERC20.transfer.selector, recipient, 7 ether)
        );
        
        // First execute the main transfer
        vm.startPrank(user);
        token.transfer(recipient, 7 ether);
        vm.stopPrank();

        // Then execute the plugin hook which should not trigger any savings
        vm.startPrank(address(executor));
        plugin.preExecutionHook(0, address(executor), 0, data);
        vm.stopPrank();
        
        assertEq(token.balanceOf(recipient), 7 ether);
        assertEq(token.balanceOf(savingsAccount), 0); // No savings when disabled
        assertEq(token.balanceOf(user), 993 ether);
    }

    function test_OnUninstall() public {
        vm.startPrank(user);
        plugin.createAutomation(savingsAccount, 10 ether);
        plugin.onUninstall("");
        
        (address savedSavingsAccount, uint256 roundUpTo, bool enabled) = plugin.savingsAutomations(user);
        assertEq(savedSavingsAccount, address(0));
        assertEq(roundUpTo, 0);
        assertFalse(enabled);
        vm.stopPrank();
    }

    function test_NonTransferFunction() public {
        vm.startPrank(user);
        plugin.createAutomation(savingsAccount, 10 ether);
        vm.stopPrank();
        
        // Try with approve function instead of transfer
        bytes memory data = abi.encode(
            address(token),
            0,
            abi.encodeWithSelector(IERC20.approve.selector, recipient, 7 ether)
        );
        
        // Execute the plugin hook which should not trigger any savings
        vm.startPrank(address(executor));
        plugin.preExecutionHook(0, address(executor), 0, data);
        vm.stopPrank();
        
        assertEq(token.balanceOf(savingsAccount), 0); // No savings for non-transfer functions
    }
} 