// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SponsorRegistry is Ownable {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error SponsorRegistry__ZeroAddress();
    error SponsorRegistry__SponsorAlreadyRegistered();
    error SponsorRegistry__SponsorNotRegistered();
    error SponsorRegistry__InvalidGasSponsor();
    error SponsorRegistry__InvalidRouter();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event SponsorRegistered(address indexed sponsor, address indexed gasSponsor, address indexed router);

    event SponsorUnregistered(address indexed sponsor);

    event GasSponsorUpdated(address indexed sponsor, address indexed oldGasSponsor, address indexed newGasSponsor);

    event RouterUpdated(address indexed sponsor, address indexed oldRouter, address indexed newRouter);

    /*//////////////////////////////////////////////////////////////
                                STRUCT
    //////////////////////////////////////////////////////////////*/

    struct Sponsor {
        address gasSponsor;
        address router;
        bool active;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    mapping(address => Sponsor) private sponsors;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address initialOwner) Ownable(initialOwner) {
        if (initialOwner == address(0)) {
            revert SponsorRegistry__ZeroAddress();
        }
    }

    /*//////////////////////////////////////////////////////////////
                          REGISTER SPONSOR
    //////////////////////////////////////////////////////////////*/

    function registerSponsor(address sponsor, address gasSponsor, address router) external onlyOwner {
        if (sponsor == address(0)) {
            revert SponsorRegistry__ZeroAddress();
        }

        if (gasSponsor == address(0)) {
            revert SponsorRegistry__InvalidGasSponsor();
        }

        if (router == address(0)) {
            revert SponsorRegistry__InvalidRouter();
        }

        if (sponsors[sponsor].active) {
            revert SponsorRegistry__SponsorAlreadyRegistered();
        }

        sponsors[sponsor] = Sponsor({gasSponsor: gasSponsor, router: router, active: true});

        emit SponsorRegistered(sponsor, gasSponsor, router);
    }

    /*//////////////////////////////////////////////////////////////
                          REMOVE SPONSOR
    //////////////////////////////////////////////////////////////*/

    function removeSponsor(address sponsor) external onlyOwner {
        if (sponsor == address(0)) {
            revert SponsorRegistry__ZeroAddress();
        }

        if (!sponsors[sponsor].active) {
            revert SponsorRegistry__SponsorNotRegistered();
        }

        sponsors[sponsor].active = false;

        emit SponsorUnregistered(sponsor);
    }

    /*//////////////////////////////////////////////////////////////
                       UPDATE GAS SPONSOR
    //////////////////////////////////////////////////////////////*/

    function updateGasSponsor(address sponsor, address newGasSponsor) external onlyOwner {
        if (sponsor == address(0)) {
            revert SponsorRegistry__ZeroAddress();
        }

        if (newGasSponsor == address(0)) {
            revert SponsorRegistry__InvalidGasSponsor();
        }

        if (!sponsors[sponsor].active) {
            revert SponsorRegistry__SponsorNotRegistered();
        }

        address oldGasSponsor = sponsors[sponsor].gasSponsor;

        sponsors[sponsor].gasSponsor = newGasSponsor;

        emit GasSponsorUpdated(sponsor, oldGasSponsor, newGasSponsor);
    }

    /*//////////////////////////////////////////////////////////////
                          UPDATE ROUTER
    //////////////////////////////////////////////////////////////*/

    function updateRouter(address sponsor, address newRouter) external onlyOwner {
        if (sponsor == address(0)) {
            revert SponsorRegistry__ZeroAddress();
        }

        if (newRouter == address(0)) {
            revert SponsorRegistry__InvalidRouter();
        }

        if (!sponsors[sponsor].active) {
            revert SponsorRegistry__SponsorNotRegistered();
        }

        address oldRouter = sponsors[sponsor].router;

        sponsors[sponsor].router = newRouter;

        emit RouterUpdated(sponsor, oldRouter, newRouter);
    }

    /*//////////////////////////////////////////////////////////////
                            GET SPONSOR
    //////////////////////////////////////////////////////////////*/

    function getSponsor(address sponsor) external view returns (address gasSponsor, address router, bool active) {
        Sponsor memory sponsorData = sponsors[sponsor];

        return (sponsorData.gasSponsor, sponsorData.router, sponsorData.active);
    }

    /*//////////////////////////////////////////////////////////////
                          IS REGISTERED
    //////////////////////////////////////////////////////////////*/

    function isRegistered(address sponsor) external view returns (bool) {
        return sponsors[sponsor].active;
    }

    /*//////////////////////////////////////////////////////////////
                          GET GAS SPONSOR
    //////////////////////////////////////////////////////////////*/

    function getGasSponsor(address sponsor) external view returns (address) {
        return sponsors[sponsor].gasSponsor;
    }

    /*//////////////////////////////////////////////////////////////
                            GET ROUTER
    //////////////////////////////////////////////////////////////*/

    function getRouter(address sponsor) external view returns (address) {
        return sponsors[sponsor].router;
    }
}
