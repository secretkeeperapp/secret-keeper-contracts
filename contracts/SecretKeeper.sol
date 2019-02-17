pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

import "./Dictionary.sol";

contract SecretKeeper {
    using Dictionary for Dictionary.Data;
    using Dictionary for Dictionary.TestatorInfo;
    using Dictionary for Dictionary.SecretInfo;

    mapping(address => Dictionary.TestatorInfo) infoForOwner;
    mapping(address => Dictionary.Data) beneficiaryToSecrets;
    mapping(uint => Dictionary.SecretInfo) allSecrets;


    // Event emitted upon callback completion; watched from front end
    event CallbackFinished(string secret);

    address public owner;

    // Constructor called when new contract is deployed
    constructor() public {
        owner = msg.sender;
    }

    //https://ethereum.stackexchange.com/questions/49185/solidity-conversion-bytes-memory-to-uint
    //https://ethereum.stackexchange.com/questions/51229/how-to-convert-bytes-to-uint-in-solidity
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

    // Mock Enigma function
    function decryptSecretForBeneficiary(uint index) public view returns (bytes memory decryptedSecret) {
        Dictionary.Data storage secretIds = beneficiaryToSecrets[msg.sender];
        uint[] memory keys = secretIds.keys();
        require(index >= 0 && index < keys.length, "Invalid index");
        uint secretId = keys[index];
        Dictionary.SecretInfo memory secretInfo = allSecrets[secretId];
        Dictionary.TestatorInfo memory testatorInfo = infoForOwner[secretInfo.owner];
        // timeBeforeReveal is in ms.
        require(((secretInfo.timeBeforeReveal / 1000) + testatorInfo.lastCheckIn) <= now, "Time delay has not yet passed");

        return secretInfo.secret;
    }

    // adding new secret ID,
    // TODO: maybe return index of new secret ID or -1?
    // change this to add or set?
    function addTestatorSecretInfo(bytes memory secret, string memory name, uint timeBeforeReveal, address beneficiary, string memory beneficiaryNote) public {
        Dictionary.TestatorInfo storage info = infoForOwner[msg.sender];
        Dictionary.Data storage secretIds = info.secretIds;
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
        Dictionary.SecretInfo memory newSecretInfo = Dictionary.SecretInfo(secret, name, timeBeforeReveal, beneficiary, msg.sender, beneficiaryNote);
        allSecrets[result] = newSecretInfo;

        // add to benef list
        beneficiaryToSecrets[beneficiary].set(result, val);
    }

    // TODO: optimize this for gas. Find a better way to store secrets by ID.
    function editTestatorSecretInfo(uint index, bytes memory secret, string memory name, uint timeBeforeReveal, address beneficiary, string memory beneficiaryNote) public {
        deleteTestatorSecretInfoByIndex(index);
        addTestatorSecretInfo(secret, name, timeBeforeReveal, beneficiary, beneficiaryNote);
    }


    function deleteTestatorSecretInfoByIndex(uint index) public {
        Dictionary.TestatorInfo storage info = infoForOwner[msg.sender];
        Dictionary.Data storage secretIds = info.secretIds;
        uint[] memory keys = secretIds.keys();

        require(index <= keys.length, "Array index out of bounds");

        return deleteTestatorSecretInfo(keys[index]);
    }

    function deleteTestatorSecretInfo(uint secretId) public {
        // TODO: make sure to check that old ID exists
        Dictionary.SecretInfo storage oldInfo = allSecrets[secretId];
        require(oldInfo.owner == msg.sender, "Sender does not own secret");


        // delete from beneficiaryToSecrets
        Dictionary.Data storage benSecretIds = beneficiaryToSecrets[oldInfo.beneficiary];
        benSecretIds.remove(secretId);
        // delete from testator dictionary
        Dictionary.TestatorInfo storage info = infoForOwner[msg.sender];
        info.secretIds.remove(secretId);
        //delete from all allSecrets
        delete allSecrets[secretId];
    }

    // Returns last check in time and number of secrets.
    function getTestatorInfo() public view returns (uint lastCheckIn, uint numSecrets) {
        Dictionary.TestatorInfo storage info = infoForOwner[msg.sender];
        Dictionary.Data storage secretIds = info.secretIds;
        uint[] memory keys = secretIds.keys();
        return (info.lastCheckIn, keys.length);
    }

    // TODO: is there and easier way to return structs?
    // Could do this in multiple calls if necessary.
    function getSecretsForTestator() public view returns (bytes[] memory secrets, string[] memory names, uint[] memory times,address[] memory beneficiaries,address[] memory owners, string[] memory beneficiaryNotes) {
        Dictionary.TestatorInfo storage testInfo = infoForOwner[msg.sender];
        Dictionary.Data storage secretIds = testInfo.secretIds;
        uint[] memory keys = secretIds.keys();
        secrets = new bytes[](keys.length);
        names = new string[](keys.length);
        times = new uint[](keys.length);
        beneficiaries = new address[](keys.length);
        owners = new address[](keys.length);
        beneficiaryNotes = new string[](keys.length);

    for (uint i = 0; i < keys.length; i++) {
            Dictionary.SecretInfo storage secret = allSecrets[keys[i]];
            secrets[i] = secret.secret;
            names[i] = secret.name;
            times[i] = secret.timeBeforeReveal;
            beneficiaries[i] = secret.beneficiary;
            owners[i] = secret.owner;
        beneficiaryNotes[i] = secret.beneficiaryNote;
        }

        return (secrets, names, times, beneficiaries, owners, beneficiaryNotes);
    }

    function getSecretsForBeneficiary() public view returns (bytes[] memory secrets, string[] memory names, uint[] memory timeBeforeReveals,uint[] memory lastCheckIns, address[] memory owners, string[] memory beneficiaryNotes) {
        Dictionary.Data storage secretIds = beneficiaryToSecrets[msg.sender];
        uint[] memory keys = secretIds.keys();
        secrets = new bytes[](keys.length);
        names = new string[](keys.length);
        lastCheckIns = new uint[](keys.length);
        timeBeforeReveals = new uint[](keys.length);

    owners = new address[](keys.length);
        beneficiaryNotes = new string[](keys.length);

    for (uint i = 0; i < keys.length; i++) {
          Dictionary.SecretInfo storage secret = allSecrets[keys[i]];
        secrets[i] = secret.secret;
        names[i] = secret.name;
        timeBeforeReveals[i] = secret.timeBeforeReveal;
        lastCheckIns[i] = infoForOwner[secret.owner].lastCheckIn;
        owners[i] = secret.owner;
        beneficiaryNotes[i] = secret.beneficiaryNote;
    }
        return (secrets, names, timeBeforeReveals, lastCheckIns, owners,beneficiaryNotes);
    }

    function getLastCheckIn() public view returns (uint lastCheckIn) {
        return infoForOwner[msg.sender].lastCheckIn;
    }

    function checkIn() public {
        infoForOwner[msg.sender].lastCheckIn = now;
    }

}
