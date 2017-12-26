pragma solidity ^0.4.11;

import "./Token.sol";
import "./AuthenticationManager.sol";
import "./SafeMath.sol";

contract LockinManager {
    using SafeMath for uint256;

    /*Defines the structure for a lock*/
    struct Lock {
        uint256 amount;
        uint256 unlockDate;
        uint256 lockedFor;
    }
    
    /*Object of Lock*/    
    Lock lock;

    /*Value of default lock days*/
    uint256 defaultAllowedLock = 7;

    /* mapping of list of locked address with array of locks for a particular address */
    mapping (address => Lock[]) public lockedAddresses;

    /* mapping of valid contracts with their lockin timestamp */
    mapping (address => uint256) public allowedContracts;

    /* list of locked days mapped with their locked timestamp*/
    mapping (uint => uint256) public allowedLocks;

    /* Defines our interface to the token contract */
    Token token;

    /* Defines the admin contract we interface with for credentails. */
    AuthenticationManager authenticationManager;

     /* Fired whenever lock day is added by the admin. */
    event LockedDayAdded(address _admin, uint256 _daysLocked, uint256 timestamp);

     /* Fired whenever lock day is removed by the admin. */
    event LockedDayRemoved(address _admin, uint256 _daysLocked, uint256 timestamp);

     /* Fired whenever valid contract is added by the admin. */
    event ValidContractAdded(address _admin, address _validAddress, uint256 timestamp);

     /* Fired whenever valid contract is removed by the admin. */
    event ValidContractRemoved(address _admin, address _validAddress, uint256 timestamp);

    /* Create a new instance of this fund with links to other contracts that are required. */
    function LockinManager(address _token, address _authenticationManager) {
      
        /* Setup access to our other contracts and validate their versions */
        token  = Token(_token);
        authenticationManager = AuthenticationManager(_authenticationManager);
    }
   
    /* This modifier allows a method to only be called by current admins */
    modifier adminOnly {
        if (!authenticationManager.isCurrentAdmin(msg.sender)) throw;
        _;
    }

    /* This modifier allows a method to only be called by token contract */
    modifier validContractOnly {
        require(allowedContracts[msg.sender] != 0);

        _;
    }

    /* Gets the length of locked values for an account */
    function getLocks(address _owner) validContractOnly constant returns (uint256) {
        return lockedAddresses[_owner].length;
    }

    function getLock(address _owner, uint256 count) validContractOnly returns(uint256 amount, uint256 unlockDate, uint256 lockedFor) {
        amount     = lockedAddresses[_owner][count].amount;
        unlockDate = lockedAddresses[_owner][count].unlockDate;
        lockedFor  = lockedAddresses[_owner][count].lockedFor;
    }
    
    /* Gets amount for which an address is locked with locked index */
    function getLocksAmount(address _owner, uint256 count) validContractOnly returns(uint256 amount) {        
        amount = lockedAddresses[_owner][count].amount;
    }

    /* Gets unlocked timestamp for which an address is locked with locked index */
    function getLocksUnlockDate(address _owner, uint256 count) validContractOnly returns(uint256 unlockDate) {
        unlockDate = lockedAddresses[_owner][count].unlockDate;
    }

    /* Gets days for which an address is locked with locked index */
    function getLocksLockedFor(address _owner, uint256 count) validContractOnly returns(uint256 lockedFor) {
        lockedFor = lockedAddresses[_owner][count].lockedFor;
    }

    /* Locks tokens for an address for the default number of days */
    function defaultLockin(address _address, uint256 _value) validContractOnly
    {
        lockIt(_address, _value, defaultAllowedLock);
    }

    /* Locks tokens for sender for n days*/
    function lockForDays(uint256 _value, uint256 _days) 
    {
        require( ! ifInAllowedLocks(_days));        

        require(token.availableBalance(msg.sender) >= _value);
        
        lockIt(msg.sender, _value, _days);     
    }

    function lockIt(address _address, uint256 _value, uint256 _days) internal {
        // expiry will be calculated as 24 * 60 * 60
        uint256 _expiry = now + _days.mul(86400);
        lockedAddresses[_address].push(Lock(_value, _expiry, _days));        
    }

    /* Check if input day is present in locked days */
    function ifInAllowedLocks(uint256 _days) constant returns(bool) {
        return allowedLocks[_days] == 0;
    }

    /* Adds a day to our list of allowedLocks */
    function addAllowedLock(uint _day) adminOnly {

        // Fail if day is already present in locked days
        if (allowedLocks[_day] != 0)
            throw;
        
        // Add day in locked days 
        allowedLocks[_day] = now;
        LockedDayAdded(msg.sender, _day, now);
    }

    /* Remove allowed Lock */
    function removeAllowedLock(uint _day) adminOnly {

        // Fail if day doesnot exist in allowedLocks
        if ( allowedLocks[_day] ==  0)
            throw;

        /* Remove locked day  */
        allowedLocks[_day] = 0;
        LockedDayRemoved(msg.sender, _day, now);
    }

    /* Adds a address to our list of allowedContracts */
    function addValidContract(address _address) adminOnly {

        // Fail if address is already present in valid contracts
        if (allowedContracts[_address] != 0)
            throw;
        
        // add an address in allowedContracts
        allowedContracts[_address] = now;

        ValidContractAdded(msg.sender, _address, now);
    }

    /* Removes allowed contract from the list of allowedContracts */
    function removeValidContract(address _address) adminOnly {

        // Fail if address doesnot exist in allowedContracts
        if ( allowedContracts[_address] ==  0)
            throw;

        /* Remove allowed contract from allowedContracts  */
        allowedContracts[_address] = 0;

        ValidContractRemoved(msg.sender, _address, now);
    }

    /* Set default allowed lock */
    function setDefaultAllowedLock(uint _days) adminOnly {
        defaultAllowedLock = _days;
    }
}