pragma solidity ^0.4.11;

import "./AuthenticationManager.sol";
import "./LockinManager.sol";
import "./SafeMath.sol";

/* The Token itself is a simple extension of the ERC20 that allows for granting other Token contracts special rights to act on behalf of all transfers. */
contract Token {
    using SafeMath for uint256;

    /* Map all our our balances for issued tokens */
    mapping (address => uint256) public balances;

    /* Map between users and their approval addresses and amounts */
    mapping(address => mapping (address => uint256)) allowed;

    /* List of all token holders */
    address[] allTokenHolders;

    /* The name of the contract */
    string public name;

    /* The symbol for the contract */
    string public symbol;

    /* How many DPs are in use in this contract */
    uint8 public decimals;

    /* Defines the current supply of the token in its own units */
    uint256 totalSupplyAmount = 0;
    
    /* Defines the address of the Refund Manager contract which is the only contract to destroy tokens. */
    address public refundManagerContractAddress;

    /* Defines the admin contract we interface with for credentails. */
    AuthenticationManager authenticationManager;

    /* Instance of lockin contract */
    LockinManager lockinManager;

    /** @dev Returns the balance that a given address has available for transfer.
      * @param _owner The address of the token owner.
      */
    function availableBalance(address _owner) constant returns(uint256) {
        
        uint256 length =  lockinManager.getLocks(_owner);
    
        uint256 lockedValue = 0;
        
        for(uint256 i = 0; i < length; i++) {

            if(lockinManager.getLocksUnlockDate(_owner, i) > now) {
                uint256 _value = lockinManager.getLocksAmount(_owner, i);    
                lockedValue = lockedValue.add(_value);                
            }
        }
        
        return balances[_owner].sub(lockedValue);
    }

    /* Fired when the fund is eventually closed. */
    event FundClosed();
    
    /* Our transfer event to fire whenever we shift SMRT around */
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    /* Our approval event when one user approves another to control */
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

    /* Create a new instance of this fund with links to other contracts that are required. */
    function Token(address _authenticationManagerAddress) {
        // Setup defaults
        name = "PIE (Authorito Capital)";
        symbol = "PIE";
        decimals = 18;

        /* Setup access to our other contracts */
        authenticationManager = AuthenticationManager(_authenticationManagerAddress);        
    }

    modifier onlyPayloadSize(uint numwords) {
        assert(msg.data.length == numwords * 32 + 4);
        _;
    }

    /* This modifier allows a method to only be called by account readers */
    modifier accountReaderOnly {
        if (!authenticationManager.isCurrentAccountReader(msg.sender)) throw;
        _;
    }

    /* This modifier allows a method to only be called by current admins */
    modifier adminOnly {
        if (!authenticationManager.isCurrentAdmin(msg.sender)) throw;
        _;
    }   
    
    function setLockinManagerAddress(address _lockinManager) adminOnly {
        lockinManager = LockinManager(_lockinManager);
    }

    function setRefundManagerContract(address _refundManagerContractAddress) adminOnly {
        refundManagerContractAddress = _refundManagerContractAddress;
    }

    /* Transfer funds between two addresses that are not the current msg.sender - this requires approval to have been set separately and follows standard ERC20 guidelines */
    function transferFrom(address _from, address _to, uint256 _amount) onlyPayloadSize(3) returns (bool) {
        
        if (availableBalance(_from) >= _amount && allowed[_from][msg.sender] >= _amount && _amount > 0 && balances[_to].add(_amount) > balances[_to]) {
            bool isNew = balances[_to] == 0;
            balances[_from] = balances[_from].sub(_amount);
            allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_amount);
            balances[_to] = balances[_to].add(_amount);
            if (isNew)
                tokenOwnerAdd(_to);
            if (balances[_from] == 0)
                tokenOwnerRemove(_from);
            Transfer(_from, _to, _amount);
            return true;
        }
        return false;
    }

    /* Returns the total number of holders of this currency. */
    function tokenHolderCount() accountReaderOnly constant returns (uint256) {
        return allTokenHolders.length;
    }

    /* Gets the token holder at the specified index. */
    function tokenHolder(uint256 _index) accountReaderOnly constant returns (address) {
        return allTokenHolders[_index];
    }
 
    /* Adds an approval for the specified account to spend money of the message sender up to the defined limit */
    function approve(address _spender, uint256 _amount) onlyPayloadSize(2) returns (bool success) {
        allowed[msg.sender][_spender] = _amount;
        Approval(msg.sender, _spender, _amount);
        return true;
    }

    /* Gets the current allowance that has been approved for the specified spender of the owner address */
    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    /* Gets the total supply available of this token */
    function totalSupply() constant returns (uint256) {
        return totalSupplyAmount;
    }

    /* Gets the balance of a specified account */
    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

    /* Transfer the balance from owner's account to another account */
    function transfer(address _to, uint256 _amount) onlyPayloadSize(2) returns (bool) {
                
        /* Check if sender has balance and for overflows */
        if (availableBalance(msg.sender) < _amount || balances[_to].add(_amount) < balances[_to])
            return false;

        /* Do a check to see if they are new, if so we'll want to add it to our array */
        bool isRecipientNew = balances[_to] == 0;

        /* Add and subtract new balances */
        balances[msg.sender] = balances[msg.sender].sub(_amount);
        balances[_to] = balances[_to].add(_amount);
        
        /* Consolidate arrays if they are new or if sender now has empty balance */
        if (isRecipientNew)
            tokenOwnerAdd(_to);
        if (balances[msg.sender] <= 0)
            tokenOwnerRemove(msg.sender);

        /* Fire notification event */
        Transfer(msg.sender, _to, _amount);
        return true; 
    }

    /* If the specified address is not in our owner list, add them - this can be called by descendents to ensure the database is kept up to date. */
    function tokenOwnerAdd(address _addr) internal {
        /* First check if they already exist */
        uint256 tokenHolderCount = allTokenHolders.length;
        for (uint256 i = 0; i < tokenHolderCount; i++)
            if (allTokenHolders[i] == _addr)
                /* Already found so we can abort now */
                return;
        
        /* They don't seem to exist, so let's add them */
        allTokenHolders.length++;
        allTokenHolders[allTokenHolders.length - 1] = _addr;
    }

    /* If the specified address is in our owner list, remove them - this can be called by descendents to ensure the database is kept up to date. */
    function tokenOwnerRemove(address _addr) internal {
        /* Find out where in our array they are */
        uint256 tokenHolderCount = allTokenHolders.length;
        uint256 foundIndex = 0;
        bool found = false;
        uint256 i;
        for (i = 0; i < tokenHolderCount; i++)
            if (allTokenHolders[i] == _addr) {
                foundIndex = i;
                found = true;
                break;
            }
        
        /* If we didn't find them just return */
        if (!found)
            return;
        
        /* We now need to shuffle down the array */
        for (i = foundIndex; i < tokenHolderCount - 1; i++)
            allTokenHolders[i] = allTokenHolders[i + 1];
        allTokenHolders.length--;
    }

    /* Mint new tokens - this can only be done by special callers (i.e. the ICO management) during the ICO phase. */
    function mintTokens(address _address, uint256 _amount) onlyPayloadSize(2) {

        /* if it is comming from account minter */
        if ( ! authenticationManager.isCurrentAccountMinter(msg.sender))
            throw;

        /* Mint the tokens for the new address*/
        bool isNew = balances[_address] == 0;
        totalSupplyAmount = totalSupplyAmount.add(_amount);
        balances[_address] = balances[_address].add(_amount);

        lockinManager.defaultLockin(_address, _amount);        

        if (isNew)
            tokenOwnerAdd(_address);
        Transfer(0, _address, _amount);
    }

    /** This will destroy the tokens of the investor and called by sale contract only at the time of refund. */
    function destroyTokens(address _investor, uint256 tokenCount) returns (bool) {
        
        /* Can only be called by refund manager, also refund manager address must not be empty */
        if ( refundManagerContractAddress  == 0x0 || msg.sender != refundManagerContractAddress)
            throw;

        uint256 balance = availableBalance(_investor);

        if (balance < tokenCount) {
            return false;
        }

        balances[_investor] -= tokenCount;
        totalSupplyAmount -= tokenCount;

        if(balances[_investor] <= 0)
            tokenOwnerRemove(_investor);

        return true;
    }
}