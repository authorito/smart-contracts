pragma solidity ^0.4.11;

import "./AuthenticationManager.sol";
import "./Token.sol";
import "./SafeMath.sol";
import "./BTCtx.sol";

contract Tokensale {
    using SafeMath for uint256;
    
    /* Defines whether or not the  Token Contract address has yet been set.  */
    bool public tokenContractDefined = false;
    
    /* Defines whether or not we are in the Sale phase */
    bool public salePhase = true;

    /* Defines the sale price of ethereum during Sale */
    uint256 public ethereumSaleRate = 700; // The number of tokens to be minted for every ETH

    /* Defines the sale price of bitcoin during Sale */
    uint256 public bitcoinSaleRate = 14000; // The number of tokens to be minted for every BTC

    /* Defines our interface to the  Token contract. */
    Token token;

    /* Defines the admin contract we interface with for credentails. */
    AuthenticationManager authenticationManager;

    /* Claimed Transactions from btc relay. */
    mapping(uint256 => bool) public transactionsClaimed;

    /* Defines the minimum ethereum to invest during Sale */
    uint256 public minimunEthereumToInvest = 0;

    /* Defines the minimum btc to invest during Sale */
    uint256 public minimunBTCToInvest = 0;

    /* Defines our event fired when the Sale is closed */
    event SaleClosed();

    /* Defines our event fired when the Sale is reopened */
    event SaleStarted();

    /* Ethereum Rate updated by the admin. */
    event EthereumRateUpdated(uint256 rate, uint256 timestamp);

    /* Bitcoin Rate updated by the admin. */
    event BitcoinRateUpdated(uint256 rate, uint256 timestamp);

    /* Minimun Ethereum Investment updated by the admin. */
    event MinimumEthereumInvestmentUpdated(uint256 _value, uint256 timestamp);

    /* Minimun Bitcoin Investment updated by the admin. */
    event MinimumBitcoinInvestmentUpdated(uint256 _value, uint256 timestamp);

    /* Ensures that once the Sale is over this contract cannot be used until the point it is destructed. */
    modifier onlyDuringSale {

        if (!tokenContractDefined || (!salePhase)) throw;
        _;
    }

    /* This modifier allows a method to only be called by current admins */
    modifier adminOnly {
        if (!authenticationManager.isCurrentAdmin(msg.sender)) throw;
        _;
    }

    /* Create the  token sale and define the address of the main authentication Manager address. */
    function Tokensale(address _authenticationManagerAddress) {        
                
        /* Setup access to our other contracts */
        authenticationManager = AuthenticationManager(_authenticationManagerAddress);
    }

    /* Set the Token contract address as a one-time operation.  This happens after all the contracts are created and no
       other functionality can be used until this is set. */
    function setTokenContractAddress(address _tokenContractAddress) adminOnly {
        /* This can only happen once in the lifetime of this contract */
        if (tokenContractDefined)
            throw;

        /* Setup access to our other contracts */
        token = Token(_tokenContractAddress);

        tokenContractDefined = true;
    }

    /* Run this function when transaction has been verified by the btc relay */
    function processBTCTransaction(bytes txn, uint256 _txHash, address ethereumAddress, bytes20 bitcoinAddress) adminOnly returns (uint256)
    {
        /* Transaction is already claimed */
        if(transactionsClaimed[_txHash] != false) 
            throw;

        var (outputValue1, outputAddress1, outputValue2, outputAddress2) = BTC.getFirstTwoOutputs(txn);

        if(BTC.checkValueSent(txn, bitcoinAddress, 1))
        {
            require(outputValue1 >= minimunBTCToInvest);

             //multiply by exchange rate
            uint256 tokensPurchased = outputValue1 * bitcoinSaleRate * (10**10);  

            token.mintTokens(ethereumAddress, tokensPurchased);

            transactionsClaimed[_txHash] = true;
        }
        else
        {
            // value was not sent to this btc address
            throw;
        }
    }

    function btcTransactionClaimed(uint256 _txHash) returns(bool) {
        return transactionsClaimed[_txHash];
    }   
    
    // fallback function can be used to buy tokens
    function () payable {
    
        buyTokens(msg.sender);
    
    }

    /* Handle receiving ether in Sale phase - we work out how much the user has bought, allocate a suitable balance and send their change */
    function buyTokens(address beneficiary) onlyDuringSale payable {

        require(beneficiary != 0x0);
        require(validPurchase());
        
        uint256 weiAmount = msg.value;

        uint256 tokensPurchased = weiAmount.mul(ethereumSaleRate);
        
        /* Increase their new balance if they actually purchased any */
        if (tokensPurchased > 0)
        {
            token.mintTokens(beneficiary, tokensPurchased);
        }
    }

    // @return true if the transaction can buy tokens
    function validPurchase() internal constant returns (bool) {

        bool nonZeroPurchase = ( msg.value != 0 && msg.value >= minimunEthereumToInvest);
        return nonZeroPurchase;
    }

    /* Rate on which */
    function setEthereumRate(uint256 _rate) adminOnly {

        ethereumSaleRate = _rate;

        /* Audit this */
        EthereumRateUpdated(ethereumSaleRate, now);
    }

      /* Rate on which */
    function setBitcoinRate(uint256 _rate) adminOnly {

        bitcoinSaleRate = _rate;

        /* Audit this */
        BitcoinRateUpdated(bitcoinSaleRate, now);
    }    

        /* update min Ethereum to invest */
    function setMinimumEthereumToInvest(uint256 _value) adminOnly {

        minimunEthereumToInvest = _value;

        /* Audit this */
        MinimumEthereumInvestmentUpdated(_value, now);
    }    

          /* update minimum Bitcoin to invest */
    function setMinimumBitcoinToInvest(uint256 _value) adminOnly {

        minimunBTCToInvest = _value;

        /* Audit this */
        MinimumBitcoinInvestmentUpdated(_value, now);
    }

      /* Close the Sale phase and transition to execution phase */
    function close() adminOnly onlyDuringSale {

        // Close the Sale
        salePhase = false;
        SaleClosed();

        // Withdraw funds to the caller
        if (!msg.sender.send(this.balance))
            throw;
    }

    /* Open the sale phase*/
    function openSale() adminOnly {        
        salePhase = true;
        SaleStarted();
    }
}