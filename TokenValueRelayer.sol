pragma solidity ^0.4.11;
import "./AuthenticationManager.sol";

/* The TokenValue Relayer contract is responsible to keep a track of token value that can be audited at a later time. */
contract TokenValueRelayer {

    /* Represents the value of the token at a particular moment in time. */
    struct TokenValueRepresentation {
        uint256 value;
        string currency;
        uint256 timestamp;
    }

    /* An array defining all the token values in history. */
    TokenValueRepresentation[] public values;
    
    /* Defines the admin contract we interface with for credentails. */
    AuthenticationManager authenticationManager;

    /* Fired when the token value is updated by an admin. */
    event TokenValue(uint256 value, string currency, uint256 timestamp);

    /* This modifier allows a method to only be called by current admins */
    modifier adminOnly {
        if (!authenticationManager.isCurrentAdmin(msg.sender)) throw;
        _;
    }

    /* Create our contract and specify the location of other addresses. */
    function TokenValueRelayer(address _authenticationManagerAddress) {
        /* Setup access to our other contracts and validate their versions */
        authenticationManager = AuthenticationManager(_authenticationManagerAddress);
    }

    /* Returns how many token values are present in the history. */
    function tokenValueCount() constant returns (uint256 _count) {
        _count = values.length;
    }

    /* Defines the current value of the token. */
    function tokenValuePublish(uint256 _value, string _currency, uint256 _timestamp) adminOnly {
        values.length++;
        values[values.length - 1] = TokenValueRepresentation(_value, _currency,_timestamp);

        /* Audit this */
        TokenValue(_value, _currency, _timestamp);
    }
}