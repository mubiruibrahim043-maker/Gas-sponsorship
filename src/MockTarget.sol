// SPDX-License-Identifier: LicenseRef-Gas-Sponsorship-Commercial-License

pragma solidity ^0.8.35;

contract MockTarget {
    /*///////////////////////////////////////////////////////////////
                                  ERROR
    ///////////////////////////////////////////////////////////////*/

    error MockTarget__InvalidFowarder();
    error MockTarget__ZeroValue();

    /*///////////////////////////////////////////////////////////////
                                 STATE
    ///////////////////////////////////////////////////////////////*/

    address public immutable trustedForwarder;
    uint256 public value;
    address public lastUser;

    /*////////////////////////////////////////////////////////////////
                                 EVENTS
    ////////////////////////////////////////////////////////////////*/

    event ValueChanged(uint256 indexed newValue, address indexed user);

    /*/////////////////////////////////////////////////////////////////
                                 CONSTRUCTOR
    /////////////////////////////////////////////////////////////////*/

    constructor(address forwarder) {
        if (forwarder == address(0)) {
            revert MockTarget__InvalidFowarder();
        }

        trustedForwarder = forwarder;
    }

    /*//////////////////////////////////////////////////////////////////
                                 TARGET FUCTION
    //////////////////////////////////////////////////////////////////*/

    function setValue(uint256 newValue) external {
        if (newValue == 0) {
            revert MockTarget__ZeroValue();
        }
        address user = _msgSender();

        value = newValue;
        lastUser = user;

        emit ValueChanged(newValue, user);
    }

    /*///////////////////////////////////////////////////////////////////
                                  MANUAL ERC-2771 LOGIC
    //////////////////////////////////////////////////////////////////*/

    function _msgSender() internal view returns (address sender) {
        if (msg.sender == trustedForwarder) {
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            sender = msg.sender;
        }
    }
}
