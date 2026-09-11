// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {SponsorRegistry} from "../../../src/SponsorRegistry.sol";
import {GasSponsor} from "../../../src/GasSponsor.sol";
import {GasSponsorRouter} from "../../../src/GasSponsorRouter.sol";

contract InvariantTarget {
    uint256 public value;
    address public lastUser;

    function setValue(uint256 newValue) external {
        address user;

        assembly {
            user := shr(96, calldataload(sub(calldatasize(), 20)))
        }

        value = newValue;
        lastUser = user;
    }
}

/*
 * Handler
 *
 * The invariant engine calls this contract with
 * randomized values.
 *
 * The Handler performs real end-to-end executions:
 *
 * Handler
 *    ↓
 * Router
 *    ↓
 * Registry
 *    ↓
 * GasSponsor
 *    ↓
 * Target
 */
contract GasSponsorHandler is Test {
    SponsorRegistry public registry;
    GasSponsor public gasSponsor;
    GasSponsorRouter public router;
    InvariantTarget public target;

    address public owner;
    address public sponsor;
    address public relayer;
    address public user;

    uint256 public constant USER_PRIVATE_KEY = 12345;

    uint256 public successfulExecutions;

    uint256 public constant INITIAL_GAS_SPONSOR_BALANCE = 10 ether;

    uint256 public constant MAX_SPONSOR_AMOUNT = 0.1 ether;

    constructor(
        SponsorRegistry _registry,
        GasSponsor _gasSponsor,
        GasSponsorRouter _router,
        InvariantTarget _target,
        address _owner,
        address _sponsor,
        address _relayer
    ) {
        registry = _registry;
        gasSponsor = _gasSponsor;
        router = _router;
        target = _target;

        owner = _owner;
        sponsor = _sponsor;
        relayer = _relayer;

        user = vm.addr(USER_PRIVATE_KEY);
    }

    /*
     * -------------------------------------------------------------
     * MAIN RANDOM ACTION
     * -------------------------------------------------------------
     *
     * The invariant engine repeatedly calls this function.
     */
    function executeRandomTransaction(uint256 randomValue, uint256 randomSponsorAmount) public {
        /*
         * Never use zero because the target should
         * receive a meaningful value.
         */
        uint256 newValue = bound(randomValue, 1, type(uint128).max);

        /*
         * Keep reimbursement within the GasSponsor
         * balance.
         */
        uint256 sponsorAmount = bound(randomSponsorAmount, 1, MAX_SPONSOR_AMOUNT);

        /*
         * Current nonce must always be used.
         */
        uint256 nonce = router.getNonce(user);

        /*
         * Encode target call.
         */
        bytes memory data = abi.encodeWithSelector(InvariantTarget.setValue.selector, newValue);

        /*
         * Construct MetaTransaction.
         */
        GasSponsorRouter.MetaTransaction memory metaTx = GasSponsorRouter.MetaTransaction({
            user: user,
            target: address(target),
            sponsor: sponsor,
            data: data,
            nonce: nonce,
            deadline: block.timestamp + 1 hours,
            sponsorAmount: sponsorAmount
        });

        /*
         * Create EIP-712 digest.
         */
        bytes32 digest = router.getTypedDataHash(metaTx);

        /*
         * Sign as the user.
         */
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PRIVATE_KEY, digest);

        bytes memory signature = abi.encodePacked(r, s, v);

        /*
         * Execute as the relayer.
         *
         * If execution unexpectedly fails, don't let the
         * handler destroy the invariant run. Only successful
         * executions count toward our accounting.
         */
        try this.executeAsRelayer(metaTx, signature) {
            successfulExecutions++;
        } catch {}
    }

    /*
     * Execute the Router call as the relayer.
     */
    function executeAsRelayer(GasSponsorRouter.MetaTransaction memory metaTx, bytes memory signature) external {
        require(msg.sender == address(this), "ONLY_HANDLER");

        vm.prank(relayer);

        router.execute(metaTx, signature);
    }
}

/*
 * ================================================================
 *                         INVARIANT TEST
 * ================================================================
 */
contract GasSponsorSystemInvariantTest is Test {
    SponsorRegistry public registry;
    GasSponsor public gasSponsor;
    GasSponsorRouter public router;
    InvariantTarget public target;

    GasSponsorHandler public handler;

    address public owner = makeAddr("owner");

    address public sponsor = makeAddr("sponsor");

    address public relayer = makeAddr("relayer");

    uint256 public constant USER_PRIVATE_KEY = 12345;

    address public user;

    uint256 public constant INITIAL_BALANCE = 10 ether;

    uint256 public constant MAX_SPONSOR_AMOUNT = 0.1 ether;

    function setUp() public {
        /*
         * ---------------------------------------------------------
         * USER
         * ---------------------------------------------------------
         */

        user = vm.addr(USER_PRIVATE_KEY);

        /*
         * ---------------------------------------------------------
         * OWNER BALANCE
         * ---------------------------------------------------------
         */

        vm.deal(owner, 10 ether);

        /*
         * ---------------------------------------------------------
         * RELAYER BALANCE
         * ---------------------------------------------------------
         */

        vm.deal(relayer, 10 ether);

        /*
         * ---------------------------------------------------------
         * DEPLOY REGISTRY
         * ---------------------------------------------------------
         */

        registry = new SponsorRegistry(owner);

        /*
         * ---------------------------------------------------------
         * DEPLOY GAS SPONSOR
         * ---------------------------------------------------------
         */

        vm.prank(owner);

        gasSponsor = new GasSponsor(owner);

        /*
         * ---------------------------------------------------------
         * DEPLOY ROUTER
         * ---------------------------------------------------------
         */

        router = new GasSponsorRouter(address(registry));

        /*
         * ---------------------------------------------------------
         * DEPLOY TARGET
         * ---------------------------------------------------------
         */

        target = new InvariantTarget();

        /*
         * ---------------------------------------------------------
         * REGISTER SPONSOR
         * ---------------------------------------------------------
         */

        vm.prank(owner);

        registry.registerSponsor(sponsor, address(gasSponsor), address(router));

        /*
         * ---------------------------------------------------------
         * CONNECT GAS SPONSOR TO ROUTER
         * ---------------------------------------------------------
         */

        vm.prank(owner);

        gasSponsor.setRouter(address(router));

        /*
         * ---------------------------------------------------------
         * FUND GAS SPONSOR
         * ---------------------------------------------------------
         */

        vm.deal(address(gasSponsor), INITIAL_BALANCE);

        /*
         * ---------------------------------------------------------
         * CREATE HANDLER
         * ---------------------------------------------------------
         */

        handler = new GasSponsorHandler(registry, gasSponsor, router, target, owner, sponsor, relayer);

        /*
         * Tell Foundry's invariant engine that the Handler
         * contains the functions it should call.
         */
        targetContract(address(handler));
    }

    /*
     * =============================================================
     * INVARIANT 1
     * =============================================================
     *
     * The sponsor must remain registered.
     */
    function invariant_SponsorAlwaysRegistered() public view {
        assertTrue(registry.isRegistered(sponsor));
    }

    /*
     * =============================================================
     * INVARIANT 2
     * =============================================================
     *
     * The registry must continue pointing to the
     * correct GasSponsor.
     */
    function invariant_RegistryGasSponsorNeverChanges() public view {
        assertEq(registry.getGasSponsor(sponsor), address(gasSponsor));
    }

    /*
     * =============================================================
     * INVARIANT 3
     * =============================================================
     *
     * The registry must continue pointing to this Router.
     */
    function invariant_RegistryRouterNeverChanges() public view {
        assertEq(registry.getRouter(sponsor), address(router));
    }

    /*
     * =============================================================
     * INVARIANT 4
     * =============================================================
     *
     * Router must continue using the correct registry.
     */
    function invariant_RouterUsesCorrectRegistry() public view {
        assertEq(address(router.registry()), address(registry));
    }

    /*
     * =============================================================
     * INVARIANT 5
     * =============================================================
     *
     * Every successful execution consumes exactly one nonce.
     *
     * Since the user's initial nonce is zero:
     *
     * nonce == successful executions
     */
    function invariant_NonceMatchesSuccessfulExecutions() public view {
        assertEq(router.getNonce(user), handler.successfulExecutions());
    }

    /*
     * =============================================================
     * INVARIANT 6
     * =============================================================
     *
     * GasSponsor can never have more than its initial
     * balance unless somebody explicitly deposits ETH.
     *
     * Our Handler never deposits ETH.
     */
    function invariant_GasSponsorBalanceNeverIncreases() public view {
        assertLe(address(gasSponsor).balance, INITIAL_BALANCE);
    }

    /*
     * =============================================================
     * INVARIANT 7
     * =============================================================
     *
     * The GasSponsor balance can never become negative.
     *
     * Solidity's uint256 makes this automatic, but checking
     * the balance here makes the system property explicit.
     */
    function invariant_GasSponsorBalanceIsValid() public view {
        assertGe(address(gasSponsor).balance, 0);
    }
}
