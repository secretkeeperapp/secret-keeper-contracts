//pragma solidity >=0.5.0;
pragma solidity ^0.4.18;
pragma experimental ABIEncoderV2;

import "./OasisDictionary.sol";

/**
 * @title OasisSecretKeeper
 * @dev The SecretKeeper contract provides functionality to store and retrieve secrets.
**/

contract OasisSecretKeeper {
    using OasisDictionary for *;

    struct TestatorInfo {
        uint lastCheckIn;
        OasisDictionary.Data secretIds;
    }

    struct SecretInfo {
        string secret;
        string name;
        uint timeBeforeReveal;
        address beneficiary;
        address owner;
        string beneficiaryNote;
    }

    mapping(address => TestatorInfo) private infoForOwner;
    mapping(address => OasisDictionary.Data) private beneficiaryToSecrets;
    mapping(uint => SecretInfo) private allSecrets;
    SecretInfo testSecretInfo;

    event SecretUnlockSucceeded(string secret, address beneficiaryAddr);
    //event SecretUnlockFailed(string message);

    address public _owner;

    /**
     * @dev The SecretKeeper constructor sets the original `owner` of the contract to the sender
     * account when a new contract is deployed
     */
    constructor() public {
        _owner = msg.sender;
    }

    function sliceUint(bytes memory bs)
    internal pure
    returns (uint)
    {
        uint start = 0;
        if (bs.length < start + 32) {
            return 0;
        }
        uint x;
        assembly {
            x := mload(add(bs, add(0x20, start)))
        }
        return x;
    }

    // TODO: is there a way a malicious caller can somehow get a secret to be under their beneficiary address?
    function decryptSecretForBeneficiary(uint index) external view {
        OasisDictionary.Data storage secretIds = beneficiaryToSecrets[msg.sender];
        uint[] memory keys = secretIds.keys();
        require(index >= 0 && index < keys.length, "Invalid index");
        uint secretId = keys[index];
        SecretInfo memory secretInfo = allSecrets[secretId];
        TestatorInfo memory testatorInfo = infoForOwner[secretInfo.owner];
        // timeBeforeReveal is in ms.
        require(((secretInfo.timeBeforeReveal / 1000) + testatorInfo.lastCheckIn) <= now, "Time delay has not yet passed");

        emit SecretUnlockSucceeded(secretInfo.secret, msg.sender);
    }


    function testStoreString(string memory arg) {
        testSecretInfo.name = arg;
    }

    function testGetString() public returns (string) {
        return testSecretInfo.name;
    }

    // adding new secret ID,
    // TODO: maybe return index of new secret ID or -1?
    // change this to add or set?
    function addTestatorSecretInfo(string memory secret, string memory name, uint timeBeforeReveal, address beneficiary, string memory beneficiaryNote) public {
        TestatorInfo storage info = infoForOwner[msg.sender];
        OasisDictionary.Data storage secretIds = info.secretIds;
        // TODO: Make sure it's not already in the dict
        //uint result = bytesToUint(secretId);
        //bytes memory current =  secretIds.get(result);

        // Need to throw an error if this is already here.
        // TODO: add name to hash?
        bytes memory secretId = abi.encodePacked(keccak256(abi.encodePacked(msg.sender, beneficiary, secret)));

        uint result = sliceUint(secretId);

        bytes memory val = "\x20";

        // Add to dict
        secretIds.set(result, val);

        // add to allSecrets
        SecretInfo memory newSecretInfo = SecretInfo(secret, name, timeBeforeReveal, beneficiary, msg.sender, beneficiaryNote);
        allSecrets[result] = newSecretInfo;

        // add to benef list
        beneficiaryToSecrets[beneficiary].set(result, val);
    }

    // TODO: optimize this for gas. Find a better way to store secrets by ID.
    function editTestatorSecretInfo(uint index, string secret, string name, uint timeBeforeReveal, address beneficiary, string beneficiaryNote) external {
        deleteTestatorSecretInfoByIndex(index);
        addTestatorSecretInfo(secret, name, timeBeforeReveal, beneficiary, beneficiaryNote);
    }


    function deleteTestatorSecretInfoByIndex(uint index) public {
        TestatorInfo storage info = infoForOwner[msg.sender];
        OasisDictionary.Data storage secretIds = info.secretIds;
        uint[] memory keys = secretIds.keys();

        require(index <= keys.length, "Array index out of bounds");

        return deleteTestatorSecretInfo(keys[index]);
    }

    function deleteTestatorSecretInfo(uint secretId) public {
        // TODO: make sure to check that old ID exists
        SecretInfo storage oldInfo = allSecrets[secretId];
        require(oldInfo.owner == msg.sender, "Sender does not own secret");


        // delete from beneficiaryToSecrets
        OasisDictionary.Data storage benSecretIds = beneficiaryToSecrets[oldInfo.beneficiary];
        benSecretIds.remove(secretId);
        // delete from testator OasisDictionary
        TestatorInfo storage info = infoForOwner[msg.sender];
        info.secretIds.remove(secretId);
        //delete from all allSecrets
        delete allSecrets[secretId];
    }

    // Returns last check in time and number of secrets.
    function getTestatorInfo() external view returns (uint lastCheckIn, uint numSecrets) {
        TestatorInfo storage info = infoForOwner[msg.sender];
        OasisDictionary.Data storage secretIds = info.secretIds;
        uint[] memory keys = secretIds.keys();
        return (info.lastCheckIn, keys.length);
    }

    function getSingleSecretForTestator() public view returns (string secrets, string name, uint time, address beneficiary, address owner, string beneficiaryNote) {
        TestatorInfo storage testInfo = infoForOwner[msg.sender];
        OasisDictionary.Data storage secretIds = testInfo.secretIds;
        uint[] memory keys = secretIds.keys();

        for (uint i = 0; i < keys.length; i++) {
            SecretInfo storage secret = allSecrets[keys[0]];
            secrets = secret.secret;
            name = secret.name;
            time = secret.timeBeforeReveal;
            beneficiary = secret.beneficiary;
            owner = secret.owner;
            beneficiaryNote = secret.beneficiaryNote;
        }
    }

    function getNumSecretsForTestator() public view returns (uint) {
        TestatorInfo storage testInfo = infoForOwner[msg.sender];
        OasisDictionary.Data storage secretIds = testInfo.secretIds;
        uint[] memory keys = secretIds.keys();
        return keys.length;
    }

    // TODO: this is a problem. If the msg.sender isn't authenticated, then
    // a call() can be made to get secrets for another user.
    function getSecretForTestator(uint index) public view returns (string secret, string name, uint time, address beneficiary, address owner, string beneficiaryNote) {
        TestatorInfo storage testInfo = infoForOwner[msg.sender];
        OasisDictionary.Data storage secretIds = testInfo.secretIds;
        uint[] memory keys = secretIds.keys();
        require(index >= 0, "Index must be positive or 0");
        require(index < keys.length, "Index must be less than the number of secrets");

        SecretInfo storage secretInfo = allSecrets[keys[index]];
    return (secretInfo.secret, secretInfo.name, secretInfo.timeBeforeReveal, secretInfo.beneficiary, secretInfo.owner, secretInfo.beneficiaryNote);
    }

    // TODO: is there and easier way to return structs?
    // Could do this in multiple calls if necessary.
    function getSecretsForTestator() public view returns (string[] memory secrets, string[] memory names, uint[] memory times,address[] memory beneficiaries,address[] memory owners, string[] memory beneficiaryNotes) {
        TestatorInfo storage testInfo = infoForOwner[msg.sender];
        OasisDictionary.Data storage secretIds = testInfo.secretIds;
        uint[] memory keys = secretIds.keys();
        secrets = new string[](keys.length);
        names = new string[](keys.length);
        times = new uint[](keys.length);
        beneficiaries = new address[](keys.length);
        owners = new address[](keys.length);
        beneficiaryNotes = new string[](keys.length);

        for (uint i = 0; i < keys.length; i++) {
            SecretInfo storage secret = allSecrets[keys[i]];
            secrets[i] = secret.secret;
            names[i] = secret.name;
            times[i] = secret.timeBeforeReveal;
            beneficiaries[i] = secret.beneficiary;
            owners[i] = secret.owner;
            beneficiaryNotes[i] = secret.beneficiaryNote;
        }

        return (secrets, names, times, beneficiaries, owners, beneficiaryNotes);
    }

    function getNumSecretsForBeneficiary() public view returns (uint) {
        OasisDictionary.Data storage secretIds = beneficiaryToSecrets[msg.sender];
        uint[] memory keys = secretIds.keys();
        return keys.length;
    }

    // TODO: this is a problem. If the msg.sender isn't authenticated, then
    // a call() can be made to get secrets for another user.
    function getSecretForBeneficiary(uint index) public view returns (string secret, string name, uint timeBeforeReveal, uint lastCheckIn, address owner, string beneficiaryNote) {
        OasisDictionary.Data storage secretIds = beneficiaryToSecrets[msg.sender];
        uint[] memory keys = secretIds.keys();

        require(index >= 0, "Index must be positive or 0");
        require(index < keys.length, "Index must be less than the number of secrets");

        SecretInfo storage secretInfo = allSecrets[keys[index]];
        return (secretInfo.secret, secretInfo.name, secretInfo.timeBeforeReveal, infoForOwner[secretInfo.owner].lastCheckIn, secretInfo.owner, secretInfo.beneficiaryNote);
    }

    function getSecretsForBeneficiary() external view returns (string[] memory secrets, string[] memory names, uint[] memory timeBeforeReveals,uint[] memory lastCheckIns, address[] memory owners, string[] memory beneficiaryNotes) {
        OasisDictionary.Data storage secretIds = beneficiaryToSecrets[msg.sender];
        uint[] memory keys = secretIds.keys();
        secrets = new string[](keys.length);
        names = new string[](keys.length);
        lastCheckIns = new uint[](keys.length);
        timeBeforeReveals = new uint[](keys.length);

        owners = new address[](keys.length);
        beneficiaryNotes = new string[](keys.length);

        for (uint i = 0; i < keys.length; i++) {
            SecretInfo storage secret = allSecrets[keys[i]];
            secrets[i] = secret.secret;
            names[i] = secret.name;
            timeBeforeReveals[i] = secret.timeBeforeReveal;
            lastCheckIns[i] = infoForOwner[secret.owner].lastCheckIn;
            owners[i] = secret.owner;
            beneficiaryNotes[i] = secret.beneficiaryNote;
        }
        return (secrets, names, timeBeforeReveals, lastCheckIns, owners,beneficiaryNotes);
    }

    function getLastCheckIn() external view returns (uint lastCheckIn) {
        return infoForOwner[msg.sender].lastCheckIn;
    }

    function checkIn() external {
        infoForOwner[msg.sender].lastCheckIn = now;
    }

}
