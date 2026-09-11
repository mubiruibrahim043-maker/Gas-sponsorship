// SPDX-License-Identifier: LicenseRef-Gas-Sponsorship-Commercial-License
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {GasSponsor} from "../../../src/GasSponsor.sol";
import {SponsorRegistry} from "../../../src/SponsorRegistry.sol";
import {GasSponsorRouter} from "../../../src/GasSponsorRouter.sol";
import {MockTarget} from "../../../src/MockTarget.sol";

contract GasSponsorEconomicSecurityTest is Test {
    GasSponsor gasSponsor;
    SponsorRegistry registry;
    GasSponsorRouter router;
    MockTarget target;

    address owner;
    address sponsor;
    address relayer1;
    address relayer2;
    address user1;
    address user2;

    uint256 constant USER1_PK = 111;
    uint256 constant USER2_PK = 222;

    function setUp() public {
        owner = makeAddr("owner");
        sponsor = makeAddr("sponsor");
        relayer1 = makeAddr("relayer1");
        relayer2 = makeAddr("relayer2");

        user1 = vm.addr(USER1_PK);
        user2 = vm.addr(USER2_PK);

        registry = new SponsorRegistry(owner);
        gasSponsor = new GasSponsor(owner);
        router = new GasSponsorRouter(address(registry));
        target = new MockTarget(address(router));

        vm.prank(owner);
        gasSponsor.setRouter(address(router));

        vm.prank(owner);
        registry.registerSponsor(sponsor, address(gasSponsor), address(router));

        vm.deal(address(gasSponsor), 10 ether);

        vm.prank(owner);
        gasSponsor.setMaxGasPerTransaction(11 ether);
    }

    function signMetaTx(uint256 pk, address user, uint256 nonce, uint256 sponsorAmount)
        internal
        view
        returns (GasSponsorRouter.MetaTransaction memory metaTx, bytes memory signature)
    {
        metaTx = GasSponsorRouter.MetaTransaction({
            user: user,
            target: address(target),
            sponsor: sponsor,
            data: abi.encodeCall(MockTarget.setValue, (777)),
            nonce: nonce,
            deadline: block.timestamp + 1 hours,
            sponsorAmount: sponsorAmount
        });

        bytes32 digest = router.getTypedDataHash(metaTx);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);

        signature = abi.encodePacked(r, s, v);
    }

    /*//////////////////////////////////////////////////////////////
                    TEST 1 — LARGE REIMBURSEMENT
    //////////////////////////////////////////////////////////////*/

    function testLargeSponsorAmountPaysEntireBalance() public {
        (GasSponsorRouter.MetaTransaction memory metaTx, bytes memory signature) =
            signMetaTx(USER1_PK, user1, 0, 10 ether);

        vm.prank(relayer1);
        router.execute(metaTx, signature);

        assertEq(address(gasSponsor).balance, 0);
        assertEq(relayer1.balance, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                TEST 2 — CANNOT PAY MORE THAN BALANCE
    //////////////////////////////////////////////////////////////*/

    function testCannotDrainMoreThanSponsorBalance() public {
        (GasSponsorRouter.MetaTransaction memory metaTx, bytes memory signature) =
            signMetaTx(USER1_PK, user1, 0, 11 ether);

        vm.expectRevert(GasSponsor.GasSponsor__InsufficientBalance.selector);

        vm.prank(relayer1);
        router.execute(metaTx, signature);

        assertEq(address(gasSponsor).balance, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                TEST 3 — MULTIPLE USERS SHARE BALANCE
    //////////////////////////////////////////////////////////////*/

    function testMultipleUsersConsumeSponsorBalance() public {
        (GasSponsorRouter.MetaTransaction memory tx1, bytes memory sig1) = signMetaTx(USER1_PK, user1, 0, 4 ether);

        vm.prank(relayer1);
        router.execute(tx1, sig1);

        (GasSponsorRouter.MetaTransaction memory tx2, bytes memory sig2) = signMetaTx(USER2_PK, user2, 0, 5 ether);

        vm.prank(relayer2);
        router.execute(tx2, sig2);

        assertEq(address(gasSponsor).balance, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                TEST 4 — SPONSOR RUNS OUT OF FUNDS
    //////////////////////////////////////////////////////////////*/

    function testSponsorOutOfFundsRevertsLaterTransactions() public {
        (GasSponsorRouter.MetaTransaction memory tx1, bytes memory sig1) = signMetaTx(USER1_PK, user1, 0, 9 ether);

        vm.prank(relayer1);
        router.execute(tx1, sig1);

        (GasSponsorRouter.MetaTransaction memory tx2, bytes memory sig2) = signMetaTx(USER2_PK, user2, 0, 2 ether);

        vm.expectRevert(GasSponsor.GasSponsor__InsufficientBalance.selector);

        vm.prank(relayer2);
        router.execute(tx2, sig2);

        assertEq(address(gasSponsor).balance, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                TEST 5 — DIFFERENT RELAYERS GET PAID
    //////////////////////////////////////////////////////////////*/

    function testDifferentRelayersReceivePayments() public {
        (GasSponsorRouter.MetaTransaction memory tx1, bytes memory sig1) = signMetaTx(USER1_PK, user1, 0, 1 ether);

        vm.prank(relayer1);
        router.execute(tx1, sig1);

        (GasSponsorRouter.MetaTransaction memory tx2, bytes memory sig2) = signMetaTx(USER2_PK, user2, 0, 2 ether);

        vm.prank(relayer2);
        router.execute(tx2, sig2);

        assertEq(relayer1.balance, 1 ether);
        assertEq(relayer2.balance, 2 ether);
    }

    /*//////////////////////////////////////////////////////////////
                TEST 6 — REPLAY AFTER BALANCE CHANGES
    //////////////////////////////////////////////////////////////*/

    function testReplayStillFailsAfterBalanceChanges() public {
        (GasSponsorRouter.MetaTransaction memory tx1, bytes memory sig1) = signMetaTx(USER1_PK, user1, 0, 1 ether);

        vm.prank(relayer1);
        router.execute(tx1, sig1);

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__InvalidNonce.selector);

        vm.prank(relayer2);
        router.execute(tx1, sig1);
    }

    /*//////////////////////////////////////////////////////////////
                TEST 7 — USER NONCES ARE INDEPENDENT
    //////////////////////////////////////////////////////////////*/

    function testUsersHaveIndependentNonces() public {
        (GasSponsorRouter.MetaTransaction memory tx1, bytes memory sig1) = signMetaTx(USER1_PK, user1, 0, 1 ether);

        vm.prank(relayer1);
        router.execute(tx1, sig1);

        assertEq(router.getNonce(user1), 1);
        assertEq(router.getNonce(user2), 0);
    }

    /*//////////////////////////////////////////////////////////////
                TEST 8 — OWNER CAN REFILL SPONSOR
    //////////////////////////////////////////////////////////////*/

    function testSponsorCanBeRefilled() public {
        (GasSponsorRouter.MetaTransaction memory tx1, bytes memory sig1) = signMetaTx(USER1_PK, user1, 0, 9 ether);

        vm.prank(relayer1);
        router.execute(tx1, sig1);

        assertEq(address(gasSponsor).balance, 1 ether);

        vm.deal(owner, 5 ether);

        vm.prank(owner);
        (bool ok,) = address(gasSponsor).call{value: 5 ether}("");
        assertTrue(ok);

        assertEq(address(gasSponsor).balance, 6 ether);
    }
    /*//////////////////////////////////////////////////////////////
            TEST 7 — SPONSOR CANNOT PAY NEGATIVE/INVALID VALUES
    //////////////////////////////////////////////////////////////*/

    function testZeroPaymentRejectedEconomically() public {
        (GasSponsorRouter.MetaTransaction memory metaTx, bytes memory signature) = signMetaTx(USER1_PK, user1, 0, 0);

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__ZeroGasPayment.selector);

        vm.prank(relayer1);
        router.execute(metaTx, signature);
    }
}
