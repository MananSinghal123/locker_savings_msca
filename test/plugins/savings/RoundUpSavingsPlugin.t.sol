// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {RoundUpSavingsPlugin} from "../../../contracts/plugins/savings/RoundUpSavingsPlugin.sol";
import {BasePlugin} from "../../../contracts/plugins/BasePlugin.sol";
import {IPluginExecutor} from "../../../contracts/interfaces/IPluginExecutor.sol";
import {IStandardExecutor} from "../../../contracts/interfaces/IStandardExecutor.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {UserOperation} from "../../../contracts/interfaces/erc4337/UserOperation.sol";
import {PluginManifest, PluginMetadata} from "../../../contracts/interfaces/IPlugin.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract MockERC20Fail is ERC20 {
    constructor() ERC20("Mock Fail Token", "MCKF") {}
    
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        revert("Transfer failed");
    }
}

contract TestExecutor is IPluginExecutor {
    event Executed(address token, uint256 value, bytes data);
    RoundUpSavingsPlugin public plugin;

    constructor(RoundUpSavingsPlugin _plugin) {
        plugin = _plugin;
    }

    function executeFromPluginExternal(
        address target,
        uint256 value,
        bytes calldata data
    ) external payable override returns (bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);
        require(success, "Execution failed");
        emit Executed(target, value, data);
        return result;
    }

    function executeFromPlugin(bytes calldata data) external payable override returns (bytes memory) {
        revert("Not implemented");
    }
}

contract RoundUpSavingsPluginTest is Test {
    RoundUpSavingsPlugin public plugin;
    MockERC20 public token;
    TestExecutor public executor;
    address public user = address(0x1);
    address public savingsAccount = address(0x2);
    uint256 public constant ROUND_UP_TO = 10 ether;
    uint256 public constant INITIAL_BALANCE = 1000 ether;

    function setUp() public {
        plugin = new RoundUpSavingsPlugin();
        token = new MockERC20("Mock Token", "MTK");
        executor = new TestExecutor(plugin);

        vm.label(user, "User");
        vm.label(address(plugin), "RoundUpSavingsPlugin");
        vm.label(address(token), "Token");
        vm.label(address(executor), "Executor");
        vm.label(savingsAccount, "SavingsAccount");

        token.mint(user, INITIAL_BALANCE);
        token.mint(address(executor), INITIAL_BALANCE);

        // Approve the plugin to spend tokens
        vm.prank(user);
        token.approve(address(plugin), type(uint256).max);
    }

    function testCreateAutomation() public {
        vm.prank(user);
        plugin.createAutomation(savingsAccount, ROUND_UP_TO);

        (address savedSavingsAccount, uint256 savedRoundUpTo, bool enabled) = plugin.savingsAutomations(user);
        assertEq(savedSavingsAccount, savingsAccount);
        assertEq(savedRoundUpTo, ROUND_UP_TO);
        assertTrue(enabled);
    }

    function testPauseAutomation() public {
        vm.prank(user);
        plugin.createAutomation(savingsAccount, ROUND_UP_TO);

        vm.prank(user);
        plugin.pauseAutomation();

        (, , bool enabled) = plugin.savingsAutomations(user);
        assertFalse(enabled);
    }

    function testUpdateAutomation() public {
        address newSavingsAccount = address(0x3);
        uint256 newRoundUpTo = 5 ether;

        vm.prank(user);
        plugin.createAutomation(savingsAccount, ROUND_UP_TO);

        vm.prank(user);
        plugin.createAutomation(newSavingsAccount, newRoundUpTo);

        (address savedSavingsAccount, uint256 savedRoundUpTo, bool enabled) = plugin.savingsAutomations(user);
        assertEq(savedSavingsAccount, newSavingsAccount);
        assertEq(savedRoundUpTo, newRoundUpTo);
        assertTrue(enabled);
    }

    function testOnUninstall() public {
        vm.prank(user);
        plugin.createAutomation(savingsAccount, ROUND_UP_TO);

        vm.prank(user);
        plugin.onUninstall("");

        (address savedSavingsAccount, uint256 savedRoundUpTo, bool enabled) = plugin.savingsAutomations(user);
        assertEq(savedSavingsAccount, address(0));
        assertEq(savedRoundUpTo, 0);
        assertFalse(enabled);
    }

    function testPreExecutionHookRoundUp() public {
        // Setup automation for executor
        vm.prank(address(executor));
        plugin.createAutomation(savingsAccount, ROUND_UP_TO);

        uint256 transferAmount = 25 ether;
        bytes memory transferData = abi.encodeWithSelector(
            IERC20.transfer.selector,
            address(0x4),
            transferAmount
        );

        bytes memory executeData = abi.encodeWithSelector(
            IStandardExecutor.execute.selector,
            address(token),
            0,
            transferData
        );

        vm.prank(address(executor));
        bytes memory result = plugin.preExecutionHook(0, address(executor), 0, executeData);
        assertEq(result.length, 0);

        uint256 expectedSavings = 5 ether; // Rounds up from 25 to 30
        assertEq(token.balanceOf(savingsAccount), expectedSavings);
    }

    function testPreExecutionHookInsufficientBalance() public {
        // Setup automation for executor
        vm.prank(address(executor));
        plugin.createAutomation(savingsAccount, ROUND_UP_TO);

        uint256 transferAmount = 25 ether;
        bytes memory transferData = abi.encodeWithSelector(
            IERC20.transfer.selector,
            address(0x4),
            transferAmount
        );

        bytes memory executeData = abi.encodeWithSelector(
            IStandardExecutor.execute.selector,
            address(token),
            0,
            transferData
        );

        // Set executor balance to just enough for transfer
        vm.startPrank(address(executor));
        token.approve(address(plugin), type(uint256).max);
        token.transfer(address(0x5), token.balanceOf(address(executor)) - 26 ether);
        vm.stopPrank();

        vm.prank(address(executor));
        bytes memory result = plugin.preExecutionHook(0, address(executor), 0, executeData);
        assertEq(result.length, 0);

        // Should save only 1 ether (remaining balance after transfer)
        assertEq(token.balanceOf(savingsAccount), 1 ether);
    }

    function testPreExecutionHookDisabled() public {
        // Setup automation for executor
        vm.prank(address(executor));
        plugin.createAutomation(savingsAccount, ROUND_UP_TO);

        // Pause automation
        vm.prank(address(executor));
        plugin.pauseAutomation();

        // Verify automation is disabled
        (, , bool enabled) = plugin.savingsAutomations(address(executor));
        assertFalse(enabled);

        bytes memory executeData = abi.encodeWithSelector(
            IStandardExecutor.execute.selector,
            address(token),
            0,
            abi.encodeWithSelector(IERC20.transfer.selector, address(0x4), 25 ether)
        );

        vm.prank(address(executor));
        bytes memory result = plugin.preExecutionHook(0, address(executor), 0, executeData);
        assertEq(result.length, 0);
        assertEq(token.balanceOf(savingsAccount), 0);
    }

    function testPreExecutionHookNonTransfer() public {
        // Setup automation for executor
        vm.prank(address(executor));
        plugin.createAutomation(savingsAccount, ROUND_UP_TO);

        bytes memory approveData = abi.encodeWithSelector(
            IERC20.approve.selector,
            address(0x4),
            100 ether
        );

        bytes memory executeData = abi.encodeWithSelector(
            IStandardExecutor.execute.selector,
            address(token),
            0,
            approveData
        );

        vm.prank(address(executor));
        bytes memory result = plugin.preExecutionHook(0, address(executor), 0, executeData);
        assertEq(result.length, 0);
        assertEq(token.balanceOf(savingsAccount), 0);
    }

    function testUserOpValidationFunctionReverts() public {
        UserOperation memory userOp;
        bytes32 userOpHash = bytes32(0);

        vm.expectRevert("RoundUpSavingsPlugin: use dependency for validation");
        plugin.userOpValidationFunction(0, userOp, userOpHash);
    }

    function testPluginMetadata() public {
        PluginMetadata memory metadata = plugin.pluginMetadata();
        assertEq(metadata.name, "Locker RoundUp Savings Plugin");
        assertEq(metadata.version, "1.0.0");
        assertEq(metadata.author, "Locker Team");
    }

    function testPluginManifest() public {
        PluginManifest memory manifest = plugin.pluginManifest();
        
        assertEq(manifest.dependencyInterfaceIds.length, 2);
        assertEq(manifest.executionFunctions.length, 2);
        assertEq(manifest.userOpValidationFunctions.length, 2);
        assertEq(manifest.executionHooks.length, 1);
        assertTrue(manifest.permitAnyExternalAddress);
        assertTrue(manifest.canSpendNativeToken);
    }

    function testPreExecutionHookHandlesFailures() public {
        MockERC20Fail badToken = new MockERC20Fail();
        badToken.mint(address(executor), 1000 ether);

        // Setup automation for executor
        vm.prank(address(executor));
        badToken.approve(address(plugin), type(uint256).max);
        plugin.createAutomation(savingsAccount, ROUND_UP_TO);

        bytes memory transferData = abi.encodeWithSelector(
            IERC20.transfer.selector,
            address(0x4),
            25 ether
        );

        bytes memory executeData = abi.encodeWithSelector(
            IStandardExecutor.execute.selector,
            address(badToken),
            0,
            transferData
        );

        vm.prank(address(executor));
        bytes memory result = plugin.preExecutionHook(0, address(executor), 0, executeData);
        assertEq(result.length, 0);
        assertEq(badToken.balanceOf(savingsAccount), 0);
    }
}