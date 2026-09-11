// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {GasSponsorRouter} from "../../../src/GasSponsorRouter.sol";
import {GasSponsor} from "../../../src/GasSponsor.sol";
import {SponsorRegistry} from "../../../src/SponsorRegistry.sol";
import {MockTarget} from "../../../src/MockTarget.sol";

contract RevertingGasSponsor {
    function releaseGas(address, address, uint256) external pure {
        revert("REIMBURSEMENT_FAILED");
    }
}

contract ReimbursementAttackTarget {
    GasSponsorRouter public router;

    GasSponsorRouter.MetaTransaction public maliciousMetaTx;
    bytes public maliciousSignature;

    bool public attackAttempted;
    bool public attackSucceeded;

    constructor(GasSponsorRouter _router) {
        router = _router;
    }

    function configureAttack(GasSponsorRouter.MetaTransaction calldata _metaTx, bytes calldata _signature) external {
        maliciousMetaTx = _metaTx;
        maliciousSignature = _signature;
    }

    function attack(uint256) external {
        attackAttempted = true;

        try router.execute(maliciousMetaTx, maliciousSignature) {
            attackSucceeded = true;
        } catch {
            attackSucceeded = false;
        }
    }
}

contract ReentrantTarget {
    GasSponsorRouter public router;

    GasSponsorRouter.MetaTransaction public metaTx;
    bytes public signature;

    bool public attempted;
    bool public reentrySucceeded;

    constructor(GasSponsorRouter _router) {
        router = _router;
    }

    function configure(GasSponsorRouter.MetaTransaction calldata _metaTx, bytes calldata _signature) external {
        metaTx = _metaTx;
        signature = _signature;
    }

    function setValue(uint256) external {
        attempted = true;

        try router.execute(metaTx, signature) {
            reentrySucceeded = true;
        } catch {
            reentrySucceeded = false;
        }
    }
}

contract GasSponsorFuzzTest is Test {
    GasSponsor public gasSponsor;
    SponsorRegistry public registry;
    GasSponsorRouter public router;
    MockTarget public target;

    address public relayer = address(0x5678);

    address public user;
    address public sponsor;

    uint256 public constant INITIAL_BALANCE = 10 ether;

    uint256 public constant USER_PRIVATE_KEY = 1;
    uint256 public constant SPONSOR_PRIVATE_KEY = 2;

    uint256 public constant SPONSOR_AMOUNT = 0.01 ether;

    function setUp() public {
        user = vm.addr(USER_PRIVATE_KEY);
        sponsor = vm.addr(SPONSOR_PRIVATE_KEY);

        registry = new SponsorRegistry(address(this));

        gasSponsor = new GasSponsor(address(this));

        router = new GasSponsorRouter(address(registry));

        target = new MockTarget(address(router));

        gasSponsor.setRouter(address(router));

        gasSponsor.setMaxGasPerTransaction(INITIAL_BALANCE);

        registry.registerSponsor(sponsor, address(gasSponsor), address(router));

        vm.deal(address(gasSponsor), INITIAL_BALANCE);

        // Second vulnerability fix:
        // Sponsor explicitly authorizes the user.
        gasSponsor.setUserAuthorization(user, true);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ: RELEASE GAS
    //////////////////////////////////////////////////////////////*/

    function testFuzzReleaseGas(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        uint256 balanceBefore = relayer.balance;

        uint256 sponsorBalanceBefore = address(gasSponsor).balance;

        vm.prank(address(router));

        gasSponsor.releaseGas(user, relayer, amount);

        assertEq(address(gasSponsor).balance, sponsorBalanceBefore - amount);

        assertEq(relayer.balance, balanceBefore + amount);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: ONLY ROUTER CAN RELEASE
    //////////////////////////////////////////////////////////////*/

    function testFuzzOnlyRouterCanReleaseGas(address caller, uint256 amount) public {
        vm.assume(caller != address(router));

        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.prank(caller);

        vm.expectRevert(GasSponsor.GasSponsor__OnlyRouter.selector);

        gasSponsor.releaseGas(user, relayer, amount);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: RELEASE TO DIFFERENT RELAYERS
    //////////////////////////////////////////////////////////////*/

    function testFuzzReleaseGasToAnyRelayer(uint256 relayerPrivateKey, uint256 amount) public {
        uint256 SECP256K1_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

        relayerPrivateKey = bound(relayerPrivateKey, 1, SECP256K1_ORDER - 1);

        amount = bound(amount, 1, INITIAL_BALANCE);

        address fuzzRelayer = vm.addr(relayerPrivateKey);

        uint256 balanceBefore = fuzzRelayer.balance;

        vm.prank(address(router));

        gasSponsor.releaseGas(user, fuzzRelayer, amount);

        assertEq(fuzzRelayer.balance, balanceBefore + amount);
    }

    /*//////////////////////////////////////////////////////////////
                    FUZZ: BALANCE NEVER GOES NEGATIVE
    //////////////////////////////////////////////////////////////*/

    function testFuzzSponsorBalanceAfterRelease(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        uint256 beforeBalance = address(gasSponsor).balance;

        vm.prank(address(router));

        gasSponsor.releaseGas(user, relayer, amount);

        uint256 afterBalance = address(gasSponsor).balance;

        assertEq(afterBalance, beforeBalance - amount);

        assertLe(afterBalance, beforeBalance);
    }

    // The remaining tests in your original file should stay unchanged.
}
