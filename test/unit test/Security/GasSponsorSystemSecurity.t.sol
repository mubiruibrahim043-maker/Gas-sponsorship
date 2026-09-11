// SPDX-License-Identifier: LicenseRef-Gas-Sponsorship-Commercial-License
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {GasSponsor} from "../../../src/GasSponsor.sol";
import {SponsorRegistry} from "../../../src/SponsorRegistry.sol";
import {GasSponsorRouter} from "../../../src/GasSponsorRouter.sol";
import {MockTarget} from "../../../src/MockTarget.sol";

//////////////////////////////////////////////////////////////
// Reentrancy attack target
//////////////////////////////////////////////////////////////

contract ReentrantTarget {
    GasSponsorRouter public router;

    GasSponsorRouter.MetaTransaction public storedMetaTx;
    bytes public storedSignature;

    bool public reentryAttempted;
    bool public reentryFailed;

    constructor(GasSponsorRouter _router) {
        router = _router;
    }

    function configure(GasSponsorRouter.MetaTransaction calldata metaTx, bytes calldata signature) external {
        storedMetaTx = metaTx;
        storedSignature = signature;
    }

    fallback() external payable {
        reentryAttempted = true;

        try router.execute(storedMetaTx, storedSignature) {
            reentryFailed = false;
        } catch {
            reentryFailed = true;
        }
    }

    receive() external payable {}
}

contract ReentrantOwner {
    GasSponsor public gasSponsor;
    uint256 public withdrawals;

    function setGasSponsor(GasSponsor _gasSponsor) external {
        gasSponsor = _gasSponsor;
    }

    function attack(uint256 amount) external {
        gasSponsor.withdraw(amount);
    }

    receive() external payable {
        withdrawals++;

        if (address(gasSponsor).balance >= 1 ether) {
            gasSponsor.withdraw(1 ether);
        }
    }
}
//////////////////////////////////////////////////////////////
// Reverting relayer
//////////////////////////////////////////////////////////////

contract RevertingRelayer {
    receive() external payable {
        revert();
    }
}

//////////////////////////////////////////////////////////////
// Security tests
//////////////////////////////////////////////////////////////

contract GasSponsorSystemSecurityTest is Test {
    GasSponsor public gasSponsor;
    SponsorRegistry public registry;
    GasSponsorRouter public router;
    MockTarget public target;

    address public owner;
    address public sponsor;
    address public relayer;
    address public user;

    uint256 internal constant USER_PRIVATE_KEY = 0xA11CE;

    //////////////////////////////////////////////////////////////
    // SETUP
    //////////////////////////////////////////////////////////////

    function setUp() public {
        owner = makeAddr("owner");
        sponsor = makeAddr("sponsor");
        relayer = makeAddr("relayer");

        user = vm.addr(USER_PRIVATE_KEY);

        // Deploy Registry
        registry = new SponsorRegistry(owner);

        // Deploy GasSponsor
        gasSponsor = new GasSponsor(owner);

        // Deploy Router
        router = new GasSponsorRouter(address(registry));

        // Deploy target using Router as trusted forwarder
        target = new MockTarget(address(router));

        // Configure GasSponsor
        vm.prank(owner);
        gasSponsor.setRouter(address(router));

        // Register sponsor
        vm.prank(owner);
        registry.registerSponsor(sponsor, address(gasSponsor), address(router));

        // Fund GasSponsor
        vm.deal(address(gasSponsor), 10 ether);

        // Configure maximum gas sponsorship
        vm.prank(owner);

        gasSponsor.setMaxGasPerTransaction(1 ether);

        vm.prank(owner);

        gasSponsor.setMaxGasPerTransaction(1 ether);
    }

    //////////////////////////////////////////////////////////////
    // HELPERS
    //////////////////////////////////////////////////////////////

    function _buildMetaTx(
        address targetAddress,
        address sponsorAddress,
        bytes memory data,
        uint256 nonce,
        uint256 deadline,
        uint256 sponsorAmount
    ) internal view returns (GasSponsorRouter.MetaTransaction memory metaTx) {
        metaTx = GasSponsorRouter.MetaTransaction({
            user: user,
            target: targetAddress,
            sponsor: sponsorAddress,
            data: data,
            nonce: nonce,
            deadline: deadline,
            sponsorAmount: sponsorAmount
        });
    }

    function _sign(GasSponsorRouter.MetaTransaction memory metaTx) internal view returns (bytes memory signature) {
        bytes32 digest = router.getTypedDataHash(metaTx);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PRIVATE_KEY, digest);

        signature = abi.encodePacked(r, s, v);
    }

    function _validMetaTx(uint256 amount) internal view returns (GasSponsorRouter.MetaTransaction memory metaTx) {
        metaTx = _buildMetaTx(
            address(target),
            sponsor,
            abi.encodeCall(MockTarget.setValue, (123)),
            router.getNonce(user),
            block.timestamp + 1 hours,
            amount
        );
    }

    //////////////////////////////////////////////////////////////
    // 1. REPLAY ATTACK
    //////////////////////////////////////////////////////////////

    function testSecurity_ReplaySignedMetaTransactionFails() public {
        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(0.1 ether);

        bytes memory signature = _sign(metaTx);

        // First execution succeeds
        vm.prank(relayer);

        router.execute(metaTx, signature);

        // Second execution must fail
        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__InvalidNonce.selector);

        vm.prank(relayer);

        router.execute(metaTx, signature);
    }

    //////////////////////////////////////////////////////////////
    // 2. MODIFY TARGET
    //////////////////////////////////////////////////////////////

    function testSecurity_ModifiedTargetInvalidatesSignature() public {
        GasSponsorRouter.MetaTransaction memory signedTx = _validMetaTx(0.1 ether);

        bytes memory signature = _sign(signedTx);

        // Attacker changes target
        signedTx.target = address(0xBEEF);

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__InvalidSignature.selector);

        vm.prank(relayer);

        router.execute(signedTx, signature);
    }

    //////////////////////////////////////////////////////////////
    // 3. MODIFY CALLDATA
    //////////////////////////////////////////////////////////////

    function testSecurity_ModifiedDataInvalidatesSignature() public {
        GasSponsorRouter.MetaTransaction memory signedTx = _validMetaTx(0.1 ether);

        bytes memory signature = _sign(signedTx);

        // Change signed calldata
        signedTx.data = abi.encodeCall(MockTarget.setValue, (999));

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__InvalidSignature.selector);

        vm.prank(relayer);

        router.execute(signedTx, signature);
    }

    //////////////////////////////////////////////////////////////
    // 4. MODIFY SPONSOR AMOUNT
    //////////////////////////////////////////////////////////////

    function testSecurity_ModifiedSponsorAmountInvalidatesSignature() public {
        GasSponsorRouter.MetaTransaction memory signedTx = _validMetaTx(0.1 ether);

        bytes memory signature = _sign(signedTx);

        // Attacker changes reimbursement
        signedTx.sponsorAmount = 1 ether;

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__InvalidSignature.selector);

        vm.prank(relayer);

        router.execute(signedTx, signature);
    }

    //////////////////////////////////////////////////////////////
    // 5. MODIFY NONCE
    //////////////////////////////////////////////////////////////

    function testSecurity_ModifiedNonceFails() public {
        GasSponsorRouter.MetaTransaction memory signedTx = _validMetaTx(0.1 ether);

        bytes memory signature = _sign(signedTx);

        signedTx.nonce += 1;

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__InvalidNonce.selector);

        vm.prank(relayer);

        router.execute(signedTx, signature);
    }

    //////////////////////////////////////////////////////////////
    // 6. EXPIRED SIGNATURE
    //////////////////////////////////////////////////////////////

    function testSecurity_ExpiredSignatureFails() public {
        GasSponsorRouter.MetaTransaction memory metaTx = _buildMetaTx(
            address(target),
            sponsor,
            abi.encodeCall(MockTarget.setValue, (123)),
            router.getNonce(user),
            block.timestamp - 1,
            0.1 ether
        );

        bytes memory signature = _sign(metaTx);

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__DeadlineExpired.selector);

        vm.prank(relayer);

        router.execute(metaTx, signature);
    }

    //////////////////////////////////////////////////////////////
    // 7. INACTIVE SPONSOR
    //////////////////////////////////////////////////////////////

    function testSecurity_InactiveSponsorCannotExecute() public {
        vm.prank(owner);

        registry.removeSponsor(sponsor);

        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(0.1 ether);

        bytes memory signature = _sign(metaTx);

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__SponsorNotRegistered.selector);

        vm.prank(relayer);

        router.execute(metaTx, signature);
    }

    //////////////////////////////////////////////////////////////
    // 8. WRONG ROUTER
    //////////////////////////////////////////////////////////////

    function testSecurity_WrongRegisteredRouterCannotExecute() public {
        GasSponsorRouter otherRouter = new GasSponsorRouter(address(registry));

        vm.prank(owner);

        registry.updateRouter(sponsor, address(otherRouter));

        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(0.1 ether);

        bytes memory signature = _sign(metaTx);

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__InvalidSponsorRouter.selector);

        vm.prank(relayer);

        router.execute(metaTx, signature);
    }

    //////////////////////////////////////////////////////////////
    // 9. UNAUTHORIZED REGISTRY MODIFICATION
    //////////////////////////////////////////////////////////////

    function testSecurity_UnauthorizedRegistryModificationFails() public {
        address attacker = makeAddr("attacker");

        vm.prank(attacker);

        vm.expectRevert();

        registry.updateRouter(sponsor, address(0x1234));
    }

    //////////////////////////////////////////////////////////////
    // 10. UNAUTHORIZED WITHDRAWAL
    //////////////////////////////////////////////////////////////

    function testSecurity_UnauthorizedGasSponsorWithdrawalFails() public {
        address attacker = makeAddr("attacker");

        vm.prank(attacker);

        vm.expectRevert();

        gasSponsor.withdraw(1 ether);
    }

    //////////////////////////////////////////////////////////////
    // 11. DIRECT GAS RELEASE ATTACK
    //////////////////////////////////////////////////////////////

    function testSecurity_DirectReleaseGasFromAttackerFails() public {
        address attacker = makeAddr("attacker");

        vm.prank(attacker);

        vm.expectRevert(GasSponsor.GasSponsor__OnlyRouter.selector);

        gasSponsor.releaseGas(attacker, relayer, 1 ether);
    }

    //////////////////////////////////////////////////////////////
    // 12. EXCESSIVE GAS RELEASE
    //////////////////////////////////////////////////////////////

    function testSecurity_DirectReleaseGasCannotExceedBalance() public {
        vm.deal(address(gasSponsor), 0.5 ether);

        vm.prank(address(router));

        vm.expectRevert(GasSponsor.GasSponsor__InsufficientBalance.selector);

        gasSponsor.releaseGas(address(this), relayer, 0.75 ether);
    }

    //////////////////////////////////////////////////////////////
    // 13. TARGET FAILURE ROLLBACK
    //////////////////////////////////////////////////////////////

    function testSecurity_TargetFailureRollsBackNonceAndPayment() public {
        GasSponsorRouter.MetaTransaction memory metaTx = _buildMetaTx(
            address(target),
            sponsor,
            abi.encodeCall(MockTarget.setValue, (0)),
            router.getNonce(user),
            block.timestamp + 1 hours,
            0.1 ether
        );

        bytes memory signature = _sign(metaTx);

        uint256 sponsorBalanceBefore = address(gasSponsor).balance;

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__ExecutionFailed.selector);

        vm.prank(relayer);

        router.execute(metaTx, signature);

        // Nonce must roll back
        assertEq(router.getNonce(user), 0);

        // Sponsor funds must not change
        assertEq(address(gasSponsor).balance, sponsorBalanceBefore);
    }

    //////////////////////////////////////////////////////////////
    // 14. SUCCESSFUL EXECUTION
    //////////////////////////////////////////////////////////////

    function testSecurity_SuccessfulExecutionPaysExactlyRequestedAmount() public {
        uint256 amount = 0.25 ether;

        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(amount);

        bytes memory signature = _sign(metaTx);

        uint256 relayerBefore = relayer.balance;

        uint256 sponsorBefore = address(gasSponsor).balance;

        vm.prank(relayer);

        router.execute(metaTx, signature);

        assertEq(relayer.balance, relayerBefore + amount);

        assertEq(address(gasSponsor).balance, sponsorBefore - amount);

        assertEq(target.value(), 123);

        assertEq(target.lastUser(), user);

        assertEq(router.getNonce(user), 1);
    }

    //////////////////////////////////////////////////////////////
    // 15. REENTRANCY / REPLAY ATTACK
    //////////////////////////////////////////////////////////////

    function testSecurity_TargetCannotReplayDuringReentrancy() public {
        ReentrantTarget maliciousTarget = new ReentrantTarget(router);

        GasSponsorRouter.MetaTransaction memory metaTx = _buildMetaTx(
            address(maliciousTarget), sponsor, hex"", router.getNonce(user), block.timestamp + 1 hours, 0.1 ether
        );

        bytes memory signature = _sign(metaTx);

        maliciousTarget.configure(metaTx, signature);

        vm.prank(relayer);

        router.execute(metaTx, signature);

        assertTrue(maliciousTarget.reentryAttempted());

        assertTrue(maliciousTarget.reentryFailed());

        assertEq(router.getNonce(user), 1);
    }

    //////////////////////////////////////////////////////////////
    // 16. ZERO TARGET
    //////////////////////////////////////////////////////////////

    function testSecurity_ZeroTargetRejected() public {
        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(0.1 ether);

        metaTx.target = address(0);

        bytes memory signature = _sign(metaTx);

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__InvalidTarget.selector);

        vm.prank(relayer);

        router.execute(metaTx, signature);
    }

    //////////////////////////////////////////////////////////////
    // 17. ZERO SPONSOR
    //////////////////////////////////////////////////////////////

    function testSecurity_ZeroSponsorRejected() public {
        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(0.1 ether);

        metaTx.sponsor = address(0);

        bytes memory signature = _sign(metaTx);

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__ZeroAddress.selector);

        vm.prank(relayer);

        router.execute(metaTx, signature);
    }

    //////////////////////////////////////////////////////////////
    // 18. ZERO SPONSOR AMOUNT
    //////////////////////////////////////////////////////////////

    function testSecurity_ZeroSponsorAmountRejected() public {
        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(0);

        bytes memory signature = _sign(metaTx);

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__ZeroGasPayment.selector);

        vm.prank(relayer);

        router.execute(metaTx, signature);
    }

    //////////////////////////////////////////////////////////////
    // 19. ZERO USER / INVALID AUTHORIZATION
    //////////////////////////////////////////////////////////////

    function testSecurity_ZeroUserCannotAuthorizeTransaction() public {
        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(0.1 ether);

        metaTx.user = address(0);

        // Sign a completely different transaction with the real user.
        bytes memory signature = _sign(_validMetaTx(0.1 ether));

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__InvalidSignature.selector);

        vm.prank(relayer);

        router.execute(metaTx, signature);
    }

    //////////////////////////////////////////////////////////////
    // 20. EIP-712 DOMAIN SEPARATION
    //////////////////////////////////////////////////////////////

    function testSecurity_SignatureCannotBeUsedOnAnotherRouter() public {
        GasSponsorRouter otherRouter = new GasSponsorRouter(address(registry));

        GasSponsorRouter.MetaTransaction memory metaTx = _buildMetaTx(
            address(target),
            sponsor,
            abi.encodeCall(MockTarget.setValue, (123)),
            0,
            block.timestamp + 1 hours,
            0.1 ether
        );

        // Signature belongs to the first Router's EIP-712 domain.
        bytes memory signature = _sign(metaTx);

        // Try using the same signature on another Router.
        vm.expectRevert();

        vm.prank(relayer);

        otherRouter.execute(metaTx, signature);
    }

    //////////////////////////////////////////////////////////////
    // 21. REVERTING RELAYER
    //////////////////////////////////////////////////////////////

    function testSecurity_RevertingRelayerRollsBackEverything() public {
        RevertingRelayer revertingRelayer = new RevertingRelayer();

        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(0.1 ether);

        bytes memory signature = _sign(metaTx);

        uint256 sponsorBefore = address(gasSponsor).balance;

        vm.prank(address(revertingRelayer));

        vm.expectRevert(GasSponsor.GasSponsor__TransferFailed.selector);

        router.execute(metaTx, signature);

        // Target state must roll back.
        assertEq(target.value(), 0);

        // Nonce must roll back.
        assertEq(router.getNonce(user), 0);

        // Sponsor balance must roll back.
        assertEq(address(gasSponsor).balance, sponsorBefore);
    }

    //////////////////////////////////////////////////////////////
    // 22. DIRECT TARGET USER BEHAVIOR
    //////////////////////////////////////////////////////////////

    function testSecurity_TargetUsesForwardedUser() public {
        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(0.1 ether);

        bytes memory signature = _sign(metaTx);

        vm.prank(relayer);

        router.execute(metaTx, signature);

        // Target must identify the user, not the Router.
        assertEq(target.lastUser(), user);

        assertTrue(target.lastUser() != address(router));
    }

    function testSecurity_GasSponsorRejectsUnconfiguredRouter() public {
        GasSponsorRouter wrongRouter = new GasSponsorRouter(address(registry));

        // Registry still trusts the original router.
        // GasSponsor will be changed to trust wrongRouter.
        vm.prank(owner);
        gasSponsor.setRouter(address(wrongRouter));

        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(0.1 ether);

        bytes memory signature = _sign(metaTx);

        uint256 balanceBefore = address(gasSponsor).balance;

        uint256 nonceBefore = router.nonces(user);

        vm.expectRevert(GasSponsor.GasSponsor__OnlyRouter.selector);

        vm.prank(relayer);

        router.execute(metaTx, signature);

        assertEq(address(gasSponsor).balance, balanceBefore);

        assertEq(router.nonces(user), nonceBefore);
    }

    function testSecurity_OwnerReentrancy() public {
        ReentrantOwner maliciousOwner = new ReentrantOwner();

        GasSponsor maliciousGasSponsor = new GasSponsor(address(maliciousOwner));

        maliciousOwner.setGasSponsor(maliciousGasSponsor);

        vm.deal(address(maliciousGasSponsor), 10 ether);

        maliciousOwner.attack(1 ether);

        assertEq(address(maliciousGasSponsor).balance, 0);

        assertEq(address(maliciousOwner).balance, 10 ether);
    }

    function testSecurity_ZeroUserCannotExecuteEvenWithZeroSignature() public {
        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(0.1 ether);

        metaTx.user = address(0);

        bytes memory zeroSignature = new bytes(65);

        vm.expectRevert();

        vm.prank(relayer);

        router.execute(metaTx, zeroSignature);
    }

    function testSecurity_OldRouterCannotExecuteAfterRouterUpdate() public {
        // Create a new router
        GasSponsorRouter newRouter = new GasSponsorRouter(address(registry));

        // Change sponsor's registered router from the current router
        // to the new router.
        vm.prank(owner);

        registry.updateRouter(sponsor, address(newRouter));

        // The old router creates a valid transaction and signature.
        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(0.1 ether);

        bytes memory signature = _sign(metaTx);

        uint256 sponsorBalanceBefore = address(gasSponsor).balance;

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__InvalidSponsorRouter.selector);

        // Try to execute through the OLD router.
        vm.prank(relayer);

        router.execute(metaTx, signature);

        // Nothing should have been paid.
        assertEq(address(gasSponsor).balance, sponsorBalanceBefore);
    }

    function testSecurity_NewGasSponsorWithWrongRouterCannotReceiveRelease() public {
        GasSponsor newGasSponsor = new GasSponsor(owner);

        // Register the new GasSponsor in the registry,
        // but deliberately DO NOT configure its router.
        vm.prank(owner);

        registry.updateGasSponsor(sponsor, address(newGasSponsor));

        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(0.1 ether);

        bytes memory signature = _sign(metaTx);

        vm.expectRevert(GasSponsor.GasSponsor__OnlyRouter.selector);

        vm.prank(relayer);

        router.execute(metaTx, signature);
    }

    function testSecurity_ExtraDataCannotChangeForwardedUser() public {
        bytes memory maliciousData =
            abi.encodePacked(abi.encodeCall(MockTarget.setValue, (123)), bytes32(uint256(uint160(address(0xBEEF)))));

        GasSponsorRouter.MetaTransaction memory metaTx = _buildMetaTx(
            address(target), sponsor, maliciousData, router.getNonce(user), block.timestamp + 1 hours, 0.1 ether
        );

        bytes memory signature = _sign(metaTx);

        vm.prank(relayer);

        router.execute(metaTx, signature);

        // The target must still recover the signed user.
        assertEq(target.lastUser(), user);

        // The attacker-controlled address must NOT become msg.sender.
        assertTrue(target.lastUser() != address(0xBEEF));

        assertEq(target.value(), 123);
    }

    function testSecurity_RemovedSponsorCannotExecute() public {
        vm.prank(owner);

        registry.removeSponsor(sponsor);

        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(0.1 ether);

        bytes memory signature = _sign(metaTx);

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__SponsorNotRegistered.selector);

        vm.prank(relayer);

        router.execute(metaTx, signature);
    }

    function testSecurity_RemovedSponsorCanBeSafelyReRegistered() public {
        vm.startPrank(owner);

        registry.removeSponsor(sponsor);

        registry.registerSponsor(sponsor, address(gasSponsor), address(router));

        vm.stopPrank();

        (address registeredGasSponsor, address registeredRouter, bool active) = registry.getSponsor(sponsor);

        assertEq(registeredGasSponsor, address(gasSponsor));

        assertEq(registeredRouter, address(router));

        assertTrue(active);
    }

    function testSecurity_OwnerChangingGasSponsorCanRedirectFunds() public {
        GasSponsor maliciousGasSponsor = new GasSponsor(owner);

        vm.startPrank(owner);

        maliciousGasSponsor.setRouter(address(router));

        maliciousGasSponsor.setMaxGasPerTransaction(1 ether);

        registry.updateGasSponsor(sponsor, address(maliciousGasSponsor));

        vm.stopPrank();

        vm.deal(address(maliciousGasSponsor), 10 ether);

        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(1 ether);

        bytes memory signature = _sign(metaTx);

        vm.prank(relayer);

        router.execute(metaTx, signature);

        assertEq(relayer.balance, 1 ether);
    }

    function testSecurity_SponsorIsolation() public {
        address sponsorB = makeAddr("sponsorB");

        GasSponsor gasSponsorB = new GasSponsor(owner);

        GasSponsorRouter routerB = new GasSponsorRouter(address(registry));

        vm.startPrank(owner);

        // Register second sponsor
        registry.registerSponsor(sponsorB, address(gasSponsorB), address(routerB));

        // Change Sponsor A only
        registry.updateGasSponsor(sponsor, address(gasSponsorB));

        vm.stopPrank();

        (address sponsorAGas,, bool sponsorAActive) = registry.getSponsor(sponsor);

        (address sponsorBGas, address sponsorBRouter, bool sponsorBActive) = registry.getSponsor(sponsorB);

        // Sponsor A changed
        assertEq(sponsorAGas, address(gasSponsorB));

        // Sponsor B must remain untouched
        assertEq(sponsorBGas, address(gasSponsorB));

        assertEq(sponsorBRouter, address(routerB));

        assertTrue(sponsorAActive);
        assertTrue(sponsorBActive);
    }

    function testSecurity_RouterIsolation() public {
        address sponsorB = makeAddr("sponsorB");

        GasSponsor gasSponsorB = new GasSponsor(owner);

        GasSponsorRouter routerB = new GasSponsorRouter(address(registry));

        vm.prank(owner);

        registry.registerSponsor(sponsorB, address(gasSponsorB), address(routerB));

        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: user,
            target: address(target),
            sponsor: sponsorB,
            data: abi.encodeCall(MockTarget.setValue, (123)),
            nonce: 0,
            deadline: block.timestamp + 1 hours,
            sponsorAmount: 0.1 ether
        });

        bytes memory signature = _sign(metaTx);

        vm.expectRevert(GasSponsorRouter.GasSponsorRouter__InvalidSponsorRouter.selector);

        vm.prank(relayer);

        // Router A attempts to execute Sponsor B's transaction.
        router.execute(metaTx, signature);
    }

    function testSecurity_RegistryGasSponsorRouterMismatchCannotRelease() public {
        GasSponsor mismatchedGasSponsor = new GasSponsor(owner);

        // The new GasSponsor trusts a different router.
        GasSponsorRouter differentRouter = new GasSponsorRouter(address(registry));

        vm.prank(owner);

        mismatchedGasSponsor.setRouter(address(differentRouter));

        vm.deal(address(mismatchedGasSponsor), 1 ether);

        // Registry deliberately points Sponsor to:
        // GasSponsor = mismatchedGasSponsor
        // Router      = current router
        vm.prank(owner);

        registry.updateGasSponsor(sponsor, address(mismatchedGasSponsor));

        GasSponsorRouter.MetaTransaction memory metaTx = _validMetaTx(0.1 ether);

        bytes memory signature = _sign(metaTx);

        uint256 balanceBefore = address(mismatchedGasSponsor).balance;

        vm.expectRevert(GasSponsor.GasSponsor__OnlyRouter.selector);

        vm.prank(relayer);

        router.execute(metaTx, signature);

        // No funds were released.
        assertEq(address(mismatchedGasSponsor).balance, balanceBefore);
    }
}
