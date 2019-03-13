pragma solidity ^0.4.18;

contract OasisCheckIn {

    address private owner;
    mapping(address => uint) private checkIns;

    constructor() public {
        owner = msg.sender;
    }

    function checkIn() public {
        // require (msg.value >= 1 finney || msg.sender == owner, "Message value must be 0.01 ether");
        // owner.transfer(msg.value);
        checkIns[msg.sender] = now;
    }

    function lastCheckIn() public view returns (uint) {
        return checkIns[msg.sender];
    }
}
