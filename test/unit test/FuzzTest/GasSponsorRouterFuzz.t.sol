// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {GasSponsorRouter} from "../../../src/GasSponsorRouter.sol";
import {SponsorRegistry} from "../../../src/SponsorRegistry.sol";
import {GasSponsor} from "../../../src/GasSponsor.sol";
import {MockTarget} from "../../../src/MockTarget.sol";

contract ReentrantTarget {
    GasSponsorRouter public router;

    GasSponsorRouter.MetaTransaction public replayTx;
    bytes public replaySignature;

    constructor(address _router) {
        router = GasSponsorRouter(_router);
    }

    function configureAttack(GasSponsorRouter.MetaTransaction calldata metaTx, bytes calldata signature) external {
        replayTx = metaTx;
        replaySignature = signature;
    }

    function attack() external {
        router.execute(replayTx, replaySignature);
    }
}

contract RevertingTarget {
    function doSomething() external pure {
        revert("TARGET_REVERTED");
    }
}

contract TestGasSponsorRouterFuzz is Test {
    GasSponsorRouter public router;
    SponsorRegistry public registry;
    GasSponsor public gasSponsor;
    MockTarget public target;

    uint256 internal constant USER_PRIVATE_KEY = 0xA11CE;
    uint256 internal constant RELAYER_PRIVATE_KEY = 0xB0B;
    uint256 internal constant SPONSOR_PRIVATE_KEY = 0xC0DE;

    address internal user;
    address internal relayer;
    address internal sponsor;

    uint256 internal constant SPONSOR_AMOUNT = 0.01 ether;

    function setUp() public {
        user = vm.addr(USER_PRIVATE_KEY);
        relayer = vm.addr(RELAYER_PRIVATE_KEY);
        sponsor = vm.addr(SPONSOR_PRIVATE_KEY);

        registry = new SponsorRegistry(address(this));

        gasSponsor = new GasSponsor(address(this));

        router = new GasSponsorRouter(address(registry));

        target = new MockTarget(address(router));

        registry.registerSponsor(sponsor, address(gasSponsor), address(router));

        gasSponsor.setRouter(address(router));

        gasSponsor.setMaxGasPerTransaction(100 ether);

        vm.deal(address(gasSponsor), 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                         FUZZ: NONCE
    //////////////////////////////////////////////////////////////*/

    function testFuzzNonceStartsAtZero(address fuzzUser) public view {
        vm.assume(fuzzUser != address(0));

        assertEq(router.nonces(fuzzUser), 0);
    }

    /*//////////////////////////////////////////////////////////////
                     FUZZ: TYPED DATA HASH
    //////////////////////////////////////////////////////////////*/

    function testFuzzTypedDataHash(uint256 value, uint256 sponsorAmount, uint256 deadline) public view {
        value = bound(value, 1, type(uint128).max);

        sponsorAmount = bound(sponsorAmount, 1, 1 ether);

        deadline = bound(deadline, block.timestamp + 1, type(uint64).max);

        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: user,
            target: address(target),
            sponsor: sponsor,
            data: abi.encodeCall(MockTarget.setValue, (value)),
            nonce: 0,
            deadline: deadline,
            sponsorAmount: sponsorAmount
        });

        bytes32 digest = router.getTypedDataHash(metaTx);

        assertTrue(digest != bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                  FUZZ: VALID SIGNED EXECUTION
    //////////////////////////////////////////////////////////////*/

    function testFuzzExecute(uint256 value) public {
        value = bound(value, 1, type(uint128).max);

        bytes memory data = abi.encodeCall(MockTarget.setValue, (value));

        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: user,
            target: address(target),
            sponsor: sponsor,
            data: data,
            nonce: router.nonces(user),
            deadline: block.timestamp + 1 hours,
            sponsorAmount: SPONSOR_AMOUNT
        });

        bytes32 digest = router.getTypedDataHash(metaTx);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PRIVATE_KEY, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 relayerBefore = relayer.balance;

        vm.prank(relayer);

        router.execute(metaTx, signature);

        assertEq(target.value(), value);

        assertEq(target.lastUser(), user);

        assertEq(router.nonces(user), 1);

        assertEq(relayer.balance, relayerBefore + SPONSOR_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                     FUZZ: REPLAY PROTECTION
    //////////////////////////////////////////////////////////////*/

    function testFuzzReplayProtection(uint256 value) public {
        value = bound(value, 1, type(uint128).max);

        bytes memory data = abi.encodeCall(MockTarget.setValue, (value));

        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: user,
            target: address(target),
            sponsor: sponsor,
            data: data,
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            sponsorAmount: SPONSOR_AMOUNT
        });

        bytes32 digest = router.getTypedDataHash(metaTx);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PRIVATE_KEY, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(relayer);

        router.execute(metaTx, signature);

        assertEq(router.nonces(user), 1);

        // Same signed transaction must not execute again.
        vm.prank(relayer);

        vm.expectRevert();

        router.execute(metaTx, signature);
    }

    function testTargetRevertDoesNotConsumeNonce() public {
        RevertingTarget revertingTarget = new RevertingTarget();

        bytes memory data = abi.encodeWithSelector(RevertingTarget.doSomething.selector);

        uint256 nonceBefore = router.getNonce(user);
        uint256 relayerBalanceBefore = relayer.balance;
        uint256 sponsorBalanceBefore = address(gasSponsor).balance;

        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: user,
            target: address(revertingTarget),
            sponsor: sponsor,
            data: data,
            nonce: nonceBefore,
            deadline: block.timestamp + 1 hours,
            sponsorAmount: SPONSOR_AMOUNT
        });

        bytes32 digest = router.getTypedDataHash(metaTx);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PRIVATE_KEY, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__ExecutionFailed.selector);

        vm.prank(relayer);

        router.execute(metaTx, signature);

        assertEq(router.getNonce(user), nonceBefore);

        assertEq(relayer.balance, relayerBalanceBefore);

        assertEq(address(gasSponsor).balance, sponsorBalanceBefore);
    }

    function testReentrancyReplayFails() public {
        ReentrantTarget attacker = new ReentrantTarget(address(router));

        GasSponsorRouter.MetaTransaction memory malicious = GasSponsorRouter.MetaTransaction({
            user: user,
            target: address(attacker),
            sponsor: sponsor,
            data: abi.encodeWithSelector(ReentrantTarget.attack.selector),
            nonce: router.getNonce(user),
            deadline: block.timestamp + 1 hours,
            sponsorAmount: SPONSOR_AMOUNT
        });

        bytes32 digest = router.getTypedDataHash(malicious);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PRIVATE_KEY, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__ExecutionFailed.selector);

        vm.prank(relayer);

        router.execute(malicious, signature);

        assertEq(router.getNonce(user), 0);
    }
}

