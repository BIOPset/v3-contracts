pragma solidity ^0.6.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.6/AggregatorProxy.sol";

import "./BIOPTokenV3.sol";
import "./RateCalc.sol";
import "./IEBOP20.sol";


/**
 * @title Binary Options Eth Pool
 * @author github.com/BIOPset
 * @dev Pool ETH Tokens and use it for optionss
 * Biop
 */
contract BinaryOptions is ERC20 {
    using SafeMath for uint256;
    address payable public devFund;
    address payable public owner;
    address public biop;
    address public defaultRCAddress;//address of default rate calculator
    mapping(address=>uint256) public nW; //next withdraw (used for pool lock time)
    mapping(address=>address) public ePairs;//enabled pairs. price provider mapped to rate calc
    mapping(address=>uint256) public lW;//last withdraw.used for rewards calc
    mapping(address=>uint256) private pClaims;//pending claims
    mapping(address=>uint256) public iAL;//interchange at last claim 
    mapping(address=>uint256) public lST;//last stake time

    //erc20 pools stuff
    mapping(address=>bool) public ePools;//enabled pools
    mapping(address=>uint256) public altLockedAmount;



    uint256 public minT;//min time
    uint256 public maxT;//max time
    address public defaultPair;
    uint256 public lockedAmount;
    uint256 public exerciserFee = 50;//in tenth percent
    uint256 public expirerFee = 50;//in tenth percent
    uint256 public devFundBetFee = 200;//0.5%
    uint256 public poolLockSeconds = 7 days;
    uint256 public contractCreated;
    bool public open = true;
    Option[] public options;
    
    uint256 public tI = 0;//total interchange
    //reward amounts
    uint256 public fGS =    400000000000000;//first gov stake reward
    uint256 public reward = 200000000000000;
    bool public rewEn = true;//rewards enabled


    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }


    /* Types */
    struct Option {
        address payable holder;
        int256 sP;//strike
        uint256 pV;//purchase 
        uint256 lV;// purchaseAmount+possible reward for correct bet
        uint256 exp;//expiration
        bool dir;//direction (true for call)
        address pP;//price provider
        address aPA;//alt pool address 
    }

    /* Events */
     event Create(
        uint256 indexed id,
        address payable account,
        int256 sP,//strike
        uint256 lV,//locked value
        bool dir
    );
    event Payout(uint256 poolLost, address winner);
    event Exercise(uint256 indexed id);
    event Expire(uint256 indexed id);

      constructor(string memory name_, string memory symbol_, address pp_, address biop_, address rateCalc_) public ERC20(name_, symbol_){
        devFund = msg.sender;
        owner = msg.sender;
        biop = biop_;
        defaultRCAddress = rateCalc_;
        lockedAmount = 0;
        contractCreated = block.timestamp;
        ePairs[pp_] = defaultRCAddress; //default pair ETH/USD
        defaultPair = pp_;
        minT = 900;//15 minutes
        maxT = 60 minutes;
    }


    function getMaxAvailable() public view returns(uint256) {
        uint256 balance = address(this).balance;
        if (balance > lockedAmount) {
            return balance.sub(lockedAmount);
        } else {
            return 0;
        }
    }

    function getAltMaxAvailable(address erc20PoolAddress_) public view returns(uint256) {
        ERC20 alt = ERC20(erc20PoolAddress_);
        uint256 balance = alt.balanceOf(address(this));
        if (balance >  altLockedAmount[erc20PoolAddress_]) {
            return balance.sub( altLockedAmount[erc20PoolAddress_]);
        } else {
            return 0;
        }
    }

    function getOptionCount() public view returns(uint256) {
        return options.length;
    }

    function getStakingTimeBonus(address account) public view returns(uint256) {
        uint256 dif = block.timestamp.sub(lST[account]);
        uint256 bonus = dif.div(777600);//9 days
        if (dif < 777600) {
            return 1;
        }
        return bonus;
    }

    function getPoolBalanceBonus(address account) public view returns(uint256) {
        uint256 balance = balanceOf(account);
        if (balance > 0) {

            if (totalSupply() < 100) { //guard
                return 1;
            }
            

            if (balance >= totalSupply().div(2)) {//50th percentile
                return 20;
            }

            if (balance >= totalSupply().div(4)) {//25th percentile
                return 14;
            }

            if (balance >= totalSupply().div(5)) {//20th percentile
                return 10;
            }

            if (balance >= totalSupply().div(10)) {//10th percentile
                return 8;
            }

            if (balance >= totalSupply().div(20)) {//5th percentile
                return 6;
            }

            if (balance >= totalSupply().div(50)) {//2nd percentile
                return 4;
            }

            if (balance >= totalSupply().div(100)) {//1st percentile
                return 3;
            }
           
           return 2;
        } 
        return 1; 
    }

    function getOptionValueBonus(address account) public view returns(uint256) {
        uint256 dif = tI.sub(iAL[account]);
        uint256 bonus = dif.div(1000000000000000000);//1ETH
        if(bonus > 0){
            return bonus;
        }
        return 0;
    }

    //used for betting/exercise/expire calc
    function getBetSizeBonus(uint256 amount, uint256 base) public view returns(uint256) {
        uint256 betPercent = totalSupply().mul(100).div(amount);
        if(base.mul(betPercent).div(10) > 0){
            return base.mul(betPercent).div(10);
        }
        return base.div(1000);
    }

    function getCombinedStakingBonus(address account) public view returns(uint256) {
        return reward
                .mul(getStakingTimeBonus(account))
                .mul(getPoolBalanceBonus(account))
                .mul(getOptionValueBonus(account));
    }

    function getPendingClaims(address account) public view returns(uint256) {
        if (balanceOf(account) > 1) {
            //staker reward bonus
            //base*(weeks)*(poolBalanceBonus/10)*optionsBacked
            return pClaims[account].add(
                getCombinedStakingBonus(account)
            );
        } else {
            //normal rewards
            return pClaims[account];
        }
    }

    function updateLPmetrics() internal {
        lST[msg.sender] = block.timestamp;
        iAL[msg.sender] = tI;
    }
     /**
     * @dev distribute pending governance token claims to user
     */
    function claimRewards() external {
        
        BIOPTokenV3 b = BIOPTokenV3(biop);
        uint256 claims = getPendingClaims(msg.sender);
        if (balanceOf(msg.sender) > 1) {
            updateLPmetrics();
        }
        pClaims[msg.sender] = 0;
        b.updateEarlyClaim(claims);
    }

    

  

    /**
     * @dev the default price provider. This is a convenience method
     */
    function defaultPriceProvider() public view returns (address) {
        return defaultPair;
    }


    /**
     * @dev add a pool
     * @param newPool_ the address EBOP20 pool to add
     */
    function addAltPool(address newPool_) external onlyOwner {
        ePools[newPool_] = true; 
    }

    /**
     * @dev enable or disable BIOP rewards
     * @param nx_ the new position for the rewEn switch
     */
    function enableRewards(bool nx_) external onlyOwner {
        rewEn = nx_;
    }

    /**
     * @dev remove a pool
     * @param oldPool_ the address EBOP20 pool to remove
     */
    function removeAltPool(address oldPool_) external onlyOwner {
        ePools[oldPool_] = false; 
    }

    /**
     * @dev add or update a price provider to the ePairs list.
     * @param newPP_ the address of the AggregatorProxy price provider contract address to add.
     * @param rateCalc_ the address of the RateCalc to use with this trading pair.
     */
    function addPP(address newPP_, address rateCalc_) external onlyOwner {
        ePairs[newPP_] = rateCalc_; 
    }

   

    /**
     * @dev remove a price provider from the ePairs list
     * @param oldPP_ the address of the AggregatorProxy price provider contract address to remove.
     */
    function removePP(address oldPP_) external onlyOwner {
        ePairs[oldPP_] = 0x0000000000000000000000000000000000000000;
    }

    /**
     * @dev update the max time for option bets
     * @param newMax_ the new maximum time (in seconds) an option may be created for (inclusive).
     */
    function setMaxT(uint256 newMax_) external onlyOwner {
        maxT = newMax_;
    }

    /**
     * @dev update the max time for option bets
     * @param newMin_ the new minimum time (in seconds) an option may be created for (inclusive).
     */
    function setMinT(uint256 newMin_) external onlyOwner {
        minT = newMin_;
    }

    /**
     * @dev address of this contract, convenience method
     */
    function thisAddress() public view returns (address){
        return address(this);
    }

    /**
     * @dev set the fee users can recieve for exercising other users options
     * @param exerciserFee_ the new fee (in tenth percent) for exercising a options itm
     */
    function updateExerciserFee(uint256 exerciserFee_) external onlyOwner {
        require(exerciserFee_ > 1 && exerciserFee_ < 500, "invalid fee");
        exerciserFee = exerciserFee_;
    }

     /**
     * @dev set the fee users can recieve for expiring other users options
     * @param expirerFee_ the new fee (in tenth percent) for expiring a options
     */
    function updateExpirerFee(uint256 expirerFee_) external onlyOwner {
        require(expirerFee_ > 1 && expirerFee_ < 50, "invalid fee");
        expirerFee = expirerFee_;
    }

    /**
     * @dev set the fee users pay to buy an option
     * @param devFundBetFee_ the new fee (in tenth percent) to buy an option
     */
    function updateDevFundBetFee(uint256 devFundBetFee_) external onlyOwner {
        require(devFundBetFee_ == 0 || devFundBetFee_ > 50, "invalid fee");
        devFundBetFee = devFundBetFee_;
    }

     /**
     * @dev update the pool stake lock up time.
     * @param newLockSeconds_ the new lock time, in seconds
     */
    function updatePoolLockSeconds(uint256 newLockSeconds_) external onlyOwner {
        require(newLockSeconds_ >= 0 && newLockSeconds_ < 14 days, "invalid fee");
        poolLockSeconds = newLockSeconds_;
    }

    /**
     * @dev used to transfer ownership
     * @param newOwner_ the address of governance contract which takes over control
     */
    function transferOwner(address payable newOwner_) external onlyOwner {
        owner = newOwner_;
    }

    /**
     * @dev used to transfer devfund 
     * @param newDevFund the address of governance contract which takes over control
     */
    function transferDevFund(address payable newDevFund) external onlyOwner {
        devFund = newDevFund;
    }


     /**
     * @dev used to send this pool into EOL mode when a newer one is open
     */
    function closeStaking() external onlyOwner {
        open = false;
    }

   
    

    /**
     * @dev send ETH to the pool. Recieve pETH token representing your claim.
     * If rewards are available recieve BIOP governance tokens as well.
    */
    function stake() external payable {
        require(open == true, "pool deposits has closed");
        require(msg.value >= 100, "stake to small");
        if (balanceOf(msg.sender) == 0) {
            lW[msg.sender] = block.timestamp;
            pClaims[msg.sender] = pClaims[msg.sender].add(fGS);
        }
        updateLPmetrics();
        nW[msg.sender] = block.timestamp + poolLockSeconds;//this one is seperate because it isn't updated on reward claim
        
        _mint(msg.sender, msg.value);
    }

    /**
     * @dev recieve ETH from the pool. 
     * If the current time is before your next available withdraw a 1% fee will be applied.
     * @param amount The amount of pETH to send the pool.
    */
    function withdraw(uint256 amount) public {
       require (balanceOf(msg.sender) >= amount, "Insufficent Share Balance");
        lW[msg.sender] = block.timestamp;
        uint256 valueToRecieve = amount.mul(address(this).balance).div(totalSupply());
        _burn(msg.sender, amount);
        if (block.timestamp <= nW[msg.sender]) {
            //early withdraw fee
            uint256 penalty = valueToRecieve.div(100);
            require(devFund.send(penalty), "transfer failed");
            require(msg.sender.send(valueToRecieve.sub(penalty)), "transfer failed");
        } else {
            require(msg.sender.send(valueToRecieve), "transfer failed");
        }
    }

     /**
    @dev helper for getting rate
    @param pair the price provider
    @param max max pool available
    @param deposit bet amount
    @param t time
    @param k direction bool, true is call
    @return the rate
    */
    function getRate(address pair,uint256 max, uint256 deposit, int256 currentPrice, uint256 t, bool k) public view returns (uint256) {
        RateCalc rc = RateCalc(ePairs[pair]);
        
        return rc.rate(deposit, max.sub(deposit), uint256(currentPrice), t, k);
    }

     /**
    @dev Open a new call or put options.
    @param k_ type of option to buy (true for call )
    @param pp_ the address of the price provider to use (must be in the list of ePairs)
    @param t_ the time until your options expiration (must be minT < t_ > maxT)
    */
    function bet(bool k_, address pp_, uint256 t_) external payable {
        require(
            t_ >= minT && t_ <= maxT,
            "Invalid time"
        );
        require(ePairs[pp_] != 0x0000000000000000000000000000000000000000, "Invalid  price provider");
        
        AggregatorProxy priceProvider = AggregatorProxy(pp_);
        int256 lA = priceProvider.latestAnswer();
        uint256 dV;
        uint256 lT;
        uint256 oID = options.length;

        
            //normal eth bet
            require(msg.value >= 100, "bet to small");
            require(msg.value <= getMaxAvailable(), "bet to big");


            //an optional (to be choosen by contract owner) fee on each option. 
            //A % of the bet money is sent as a fee. see devFundBetFee
            if (msg.value > devFundBetFee && devFundBetFee > 0) {
                    uint256 fee = msg.value.div(devFundBetFee);
                    require(devFund.send(fee), "devFund fee transfer failed");
                    dV = msg.value.sub(fee);
            } else {
                    dV = msg.value;
            }


            uint256 lockValue = getRate(pp_, getMaxAvailable(), dV, lA, t_, k_);
            
            if (rewEn) {
                pClaims[msg.sender] = pClaims[msg.sender].add(getBetSizeBonus(dV, reward));
            }
            lT = lockValue.add(dV);
            lock(lT);
        


        Option memory op = Option(
            msg.sender,
            lA,
            dV,
            lT,
            block.timestamp + t_,//time till expiration
            k_,
            pp_,
            address(this)
        );

        options.push(op);
        tI = tI.add(lT);
        emit Create(oID, msg.sender, lA, lT, k_);
    }

    /**
    @dev Open a new call or put options with a ERC20 pool.
    @param k_ type of option to buy (true for call)
    @param pp_ the address of the price provider to use (must be in the list of ePairs)
    @param t_ the time until your options expiration (must be minT < t_ > maxT)
    @param pa_ address of alt pool
    @param a_ bet amount. 
    */function bet20(bool k_, address pp_, uint256 t_, address pa_,  uint256 a_) external payable {
        require(
            t_ >= minT && t_ <= maxT,
            "Invalid time"
        );
        require(ePairs[pp_] != 0x0000000000000000000000000000000000000000, "Invalid  price provider");
        
        AggregatorProxy priceProvider = AggregatorProxy(pp_);
        int256 lA = priceProvider.latestAnswer();
        uint256 dV;
        uint256 lT;

        require(ePools[pa_], "invalid pool");
        IEBOP20 altPool = IEBOP20(pa_);
        require(altPool.balanceOf(msg.sender) >= a_, "invalid pool");
        (dV, lT) = altPool.bet(lA, a_);
        
        Option memory op = Option(
            msg.sender,
            lA,
            dV,
            lT,
            block.timestamp + t_,//time till expiration
            k_,
            pp_,
            pa_
        );

        options.push(op);
        tI = tI.add(lT);
        emit Create(options.length-1, msg.sender, lA, lT, k_);
    }


    

     /**
     * @notice exercises a option
     * @param oID id of the option to exercise
     */
    function exercise(uint256 oID)
        external
    {
        Option memory option = options[oID];
        require(block.timestamp <= option.exp, "expiration date margin has passed");
        AggregatorProxy priceProvider = AggregatorProxy(option.pP);
        int256 lA = priceProvider.latestAnswer();
        if (option.dir) {
            //call option
            require(lA > option.sP, "price is to low");
        } else {
            //put option
            require(lA < option.sP, "price is to high");
        }


        if (option.aPA != address(this)) {
            IEBOP20 alt = IEBOP20(option.aPA);
            require(alt.payout(option.lV,option.pV, msg.sender, option.holder), "erc20 pool exercise failed");
        } else {
            //option expires ITM, we pay out
            payout(option.lV, msg.sender, option.holder);
            lockedAmount = lockedAmount.sub(option.lV);
        }
        
        emit Exercise(oID);
        if (rewEn) {
            pClaims[msg.sender] = pClaims[msg.sender].add(getBetSizeBonus(option.lV, reward));
        }
    }

     /**
     * @notice expires a option
     * @param oID id of the option to expire
     */
    function expire(uint256 oID)
        external
    {
        Option memory option = options[oID];
        require(block.timestamp > option.exp, "expiration date has not passed");


        if (option.aPA != address(this)) {
            //ERC20 option
            IEBOP20 alt = IEBOP20(option.aPA);
            require(alt.unlockAndPayExpirer(option.lV,option.pV, msg.sender), "erc20 pool exercise failed");
        } else {
            //ETH option
            unlock(option.lV, msg.sender);
            lockedAmount = lockedAmount.sub(option.lV);
        }
        emit Expire(oID);
        if (rewEn) {
            pClaims[msg.sender] = pClaims[msg.sender].add(getBetSizeBonus(option.pV, reward));
        }
    }

    /**
    @dev called by BinaryOptions contract to lock pool value coresponding to new binary options bought. 
    @param amount amount in ETH to lock from the pool total.
    */
    function lock(uint256 amount) internal {
        lockedAmount = lockedAmount.add(amount);
    }

    /**
    @dev called by BinaryOptions contract to unlock pool value coresponding to an option expiring otm. 
    @param amount amount in ETH to unlock
    @param goodSamaritan the user paying to unlock these funds, they recieve a fee
    */
    function unlock(uint256 amount, address payable goodSamaritan) internal {
        require(amount <= lockedAmount, "insufficent locked pool balance to unlock");
        uint256 fee;
        if (amount <= 10000000000000000) {//small options give bigger fee %
            fee = amount.div(exerciserFee.mul(4)).div(100);
        } else {
            fee = amount.div(exerciserFee).div(100);
        } 
        if (fee > 0) {
            require(goodSamaritan.send(fee), "good samaritan transfer failed");
        }
    }

    /**
    @dev called by BinaryOptions contract to payout pool value coresponding to binary options expiring itm. 
    @param amount amount in ETH to unlock
    @param exerciser address calling the exercise/expire function, this may the winner or another user who then earns a fee.
    @param winner address of the winner.
    @notice exerciser fees are subject to change see updateFeePercent above.
    */
    function payout(uint256 amount, address payable exerciser, address payable winner) internal {
        require(amount <= lockedAmount, "insufficent pool balance available to payout");
        require(amount <= address(this).balance, "insufficent balance in pool");
        if (exerciser != winner) {
            //good samaratin fee
            uint256 fee;
            if (amount <= 10000000000000000) {//small options give bigger fee %
                fee = amount.div(exerciserFee.mul(4)).div(100);
            } else {
                fee = amount.div(exerciserFee).div(100);
            } 
            if (fee > 0) {
                require(exerciser.send(fee), "exerciser transfer failed");
                require(winner.send(amount.sub(fee)), "winner transfer failed");
            }
        } else {  
            require(winner.send(amount), "winner transfer failed");
        }
        emit Payout(amount, winner);
    }

}