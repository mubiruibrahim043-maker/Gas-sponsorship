// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {SponsorRegistry} from "../../src/SponsorRegistry.sol";

import {GasSponsor} from "../../src/GasSponsor.sol";
import {GasSponsorRouter} from "../../src/GasSponsorRouter.sol";
import {MockTarget} from "../../src/MockTarget.sol";

contract GasSponsorRouterTest is Test {
    GasSponsor sponsor;
    GasSponsorRouter router;
    MockTarget target;
    SponsorRegistry registry;

    uint256 userPrivateKey = 0x123456;

    address user;

    uint256 relayerPrivateKey = 0x654321;

    address relayer;

    uint256 constant SPONSOR_AMOUNT = 0.01 ether;

    function setUp() public {
        user = vm.addr(userPrivateKey);
        relayer = vm.addr(relayerPrivateKey);

        // Deploy GasSponsor
        sponsor = new GasSponsor(address(this));

        // Deploy SponsorRegistry
        registry = new SponsorRegistry(address(this));

        // Deploy Router using the registry
        router = new GasSponsorRouter(address(registry));

        // Register the sponsor and its router
        registry.registerSponsor(address(sponsor), address(sponsor), address(router));

        // Tell GasSponsor which router is authorized
        sponsor.setRouter(address(router));

        // Deploy target
        target = new MockTarget(address(router));

        // Fund GasSponsor
        vm.deal(address(sponsor), 10 ether);

        // Allow the test sponsorship amount
        sponsor.setMaxGasPerTransaction(SPONSOR_AMOUNT);
    }

    function testNonceStartsAtZero() public view {
        assertEq(router.nonces(user), 0);
    }

    function testTypedDataHash() public view {
        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: user,
            target: address(target),
            sponsor: address(sponsor),
            data: abi.encodeCall(MockTarget.setValue, (100)),
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            sponsorAmount: SPONSOR_AMOUNT
        });

        bytes32 digest = router.getTypedDataHash(metaTx);

        assertTrue(digest != bytes32(0));
    }

    function testExecuteSignedTransaction() public {
        bytes memory data = abi.encodeCall(MockTarget.setValue, (100));

        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: user,
            target: address(target),
            sponsor: address(sponsor),
            data: data,
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            sponsorAmount: SPONSOR_AMOUNT
        });

        bytes32 digest = router.getTypedDataHash(metaTx);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 relayerBefore = relayer.balance;

        vm.prank(relayer);

        router.execute(metaTx, signature);

        assertEq(target.value(), 100);

        assertEq(target.lastUser(), user);

        assertEq(router.nonces(user), 1);

        assertEq(relayer.balance, relayerBefore + SPONSOR_AMOUNT);
    }

    function testExecuteWithValidSignature() public {
        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: user,
            target: address(target),
            sponsor: address(sponsor),
            data: abi.encodeCall(MockTarget.setValue, (100)),
            nonce: router.getNonce(user),
            deadline: block.timestamp + 1 hours,
            sponsorAmount: SPONSOR_AMOUNT
        });

        bytes32 digest = router.getTypedDataHash(metaTx);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 relayerBalanceBefore = relayer.balance;

        uint256 sponsorBalanceBefore = address(sponsor).balance;

        vm.prank(relayer);

        bytes memory result = router.execute(metaTx, signature);

        assertEq(router.getNonce(user), metaTx.nonce + 1);

        assertEq(target.value(), 100);

        assertEq(target.lastUser(), user);

        assertEq(relayer.balance, relayerBalanceBefore + SPONSOR_AMOUNT);

        assertEq(address(sponsor).balance, sponsorBalanceBefore - SPONSOR_AMOUNT);

        assertEq(result.length, 0);
    }

    function test_RevertWhen_TargetExecutionFails() public {
        bytes memory data = abi.encodeCall(MockTarget.setValue, (0));

        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: user,
            target: address(target),
            sponsor: address(sponsor),
            data: data,
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            sponsorAmount: SPONSOR_AMOUNT
        });

        bytes32 digest = router.getTypedDataHash(metaTx);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 relayerBefore = relayer.balance;

        uint256 sponsorBalanceBefore = address(sponsor).balance;

        vm.prank(relayer);

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__ExecutionFailed.selector);

        router.execute(metaTx, signature);

        assertEq(router.getNonce(user), 0);

        assertEq(target.value(), 0);

        assertEq(target.lastUser(), address(0));

        assertEq(relayer.balance, relayerBefore);

        assertEq(address(sponsor).balance, sponsorBalanceBefore);
    }

    function test_RevertWhen_RegistryIsZeroAddress() public {
        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__ZeroAddress.selector);

        new GasSponsorRouter(address(0));
    }

    function test_RevertWhen_SponsorIsInactive() public {
        registry.removeSponsor(address(sponsor));

        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: user,
            target: address(target),
            sponsor: address(sponsor),
            data: abi.encodeCall(MockTarget.setValue, (100)),
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            sponsorAmount: SPONSOR_AMOUNT
        });

        bytes32 digest = router.getTypedDataHash(metaTx);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(relayer);

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__SponsorNotRegistered.selector);

        router.execute(metaTx, signature);
    }

    function testGetDomainSeparator() public view {
        bytes32 domainSeparator = router.getDomainSeparator();

        assertTrue(domainSeparator != bytes32(0));
    }
}
