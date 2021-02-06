pragma solidity ^0.6.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./BIOPTokenV3.sol";
import "./BinaryOptions.sol";
import "./GovProxy.sol";
interface AccessTiers {
    /**
     * @notice Returns the rate to pay out for a given amount
     * @param power the amount of control held by user trying to access this action
     * @param total the total amount of control available
     * @return boolean of users access to this tier
     */
    function tier1(uint256 power, uint256 total) external returns (bool);

    /**
     * @notice Returns the rate to pay out for a given amount
     * @param power the amount of control held by user trying to access this action
     * @param total the total amount of control available
     * @return boolean of users access to this tier
     */
    function tier2(uint256 power, uint256 total) external returns (bool);


    /**
     * @notice Returns the rate to pay out for a given amount
     * @param power the amount of control held by user trying to access this action
     * @param total the total amount of control available
     * @return boolean of users access to this tier
     */
    function tier3(uint256 power, uint256 total) external returns (bool);


    /**
     * @notice Returns the rate to pay out for a given amount
     * @param power the amount of control held by user trying to access this action
     * @param total the total amount of control available
     * @return boolean of users access to this tier
     */
    function tier4(uint256 power, uint256 total) external returns (bool);
}

contract DelegatedAccessTiers is AccessTiers {
    using SafeMath for uint256;
    function tier1(uint256 power, uint256 total) external override returns (bool) {
        uint256 half = total.div(2);
        if (power >= half) {
            return true;
        }
        return false;
    }

    function tier2(uint256 power, uint256 total) external override returns (bool) {
        uint256 twothirds = total.div(3).mul(2);
        if (power >= twothirds) {
            return true;
        }
        return false;
    }

    function tier3(uint256 power, uint256 total) external override returns (bool) {
        uint256 threeQuarters = total.div(4).mul(3);
        if (power >= threeQuarters) {
            return true;
        }
        return false;
    }

    function tier4(uint256 power, uint256 total) external override returns (bool) {
        uint256 ninety = total.div(10).mul(9);
        if (power >= ninety) {
            return true;
        }
        return false;
    }
}



/**
 * @title DelegatedGov
 * @author github.com/Shalquiana
 * @dev governance for biopset protocol
 * @notice governance for biopset protocol
 * BIOP
 */
contract DelegatedGov {
    using SafeMath for uint256;
    address public pA;//protocol address
    address public tA;//token address
    address public aTA;//access tiers address
    address payable public pX;//proxy
    
    mapping(address=>uint256) public shas;//amounts of voting power held by each sha
    mapping(address=>address) public rep;//representative/delegate/governer currently backed by given address
    mapping(address=>uint256) public staked;//amount of BIOP they have staked
    uint256 dBIOP = 0;//the total amount of staked BIOP which has been delegated for governance

    //rewards for stakers
    uint256 public trg = 0;//total rewards generated
    mapping(address=>uint256) public lrc;//last rewards claimed at trg point for this address 
    

     constructor(address bo_, address v3_, address accessTiers_, address payable proxy_) public {
      pA = bo_;
      tA = v3_;
      aTA = accessTiers_;
      pX = proxy_;
    }


    event Stake(uint256 amount, uint256 total);
    event Withdraw(uint256 amount, uint256 total);

    function totalStaked() public view returns (uint256) {
        BIOPTokenV3 token = BIOPTokenV3(tA);
        return token.balanceOf(address(this));
    }

    /**
     * @notice stake your BIOP and begin earning rewards
     * @param amount the amount in BIOP you want to stake
     */
    function stake(uint256 amount) public {
        require(amount > 0, "invalid amount");
        BIOPTokenV3 token = BIOPTokenV3(tA);
        require(token.balanceOf(msg.sender) >= amount, "insufficent biop balance");
        require(token.transferFrom(msg.sender, address(this), amount), "staking failed");
        if (staked[msg.sender] == 0) {
            lrc[msg.sender] = trg;
        }
        staked[msg.sender] = staked[msg.sender].add(amount);
        emit Stake(amount, totalStaked());
    }

    /**
     * @notice withdraw your BIOP and stop earning rewards. You must undelegate before you can withdraw
     * @param amount the amount in BIOP you want to withdraw
     */
    function withdraw(uint256 amount) public {
        require(staked[msg.sender] >= amount, "invalid amount");
        BIOPTokenV3 token = BIOPTokenV3(tA);
        require(rep[msg.sender] ==  0x0000000000000000000000000000000000000000);
        require(token.transfer(msg.sender, amount), "staking failed");
        staked[msg.sender] = staked[msg.sender].sub(amount);

        uint256 totalBalance = token.balanceOf(address(this));
        emit Withdraw(amount, totalBalance);
    }

     /**
     * @notice delegates your voting power to a specific address(sha)
     * @param newSha the address of the delegate to voting power
     */
    function delegate(address payable newSha) public {
        BIOPTokenV3 token = BIOPTokenV3(tA);
        address oldSha = rep[msg.sender];
        if (oldSha == 0x0000000000000000000000000000000000000000) {
            dBIOP = dBIOP.add(staked[msg.sender]);
        }
        if (oldSha != 0x0000000000000000000000000000000000000000) {
            shas[oldSha] = shas[oldSha].sub(staked[msg.sender]);
        }
        shas[newSha] = shas[newSha].add(staked[msg.sender]);
        rep[msg.sender] = newSha;
    }

     /**
     * @notice undelegate your voting power. you will still earn staking rewards 
     * but your voting power won't back any delegate.
     */
    function undelegate() public {
        BIOPTokenV3 token = BIOPTokenV3(tA);
        address oldSha = rep[msg.sender];
        shas[oldSha] = shas[oldSha].sub(staked[msg.sender]);
        rep[msg.sender] =  0x0000000000000000000000000000000000000000;
        dBIOP = dBIOP.sub(staked[msg.sender]);
    }

    /** 
    * @notice base rewards since last claim
    * @param acc the account to get the answer for
    */
    function bRSLC(address acc) public view returns (uint256) {
        return trg.sub(lrc[acc]);
    }

    function pendingETHRewards(address account) public view returns (uint256) {
        BIOPTokenV3 token = BIOPTokenV3(tA);
        uint256 base = bRSLC(account);
        return base.mul(staked[account]).div(totalStaked());
    }


    function claimETHRewards() public {
        require(lrc[msg.sender] < trg, "no rewards available");
        
        BIOPTokenV3 token = BIOPTokenV3(tA);
        uint256 toSend = pendingETHRewards(msg.sender);
        lrc[msg.sender] = trg;
        require(msg.sender.send(toSend), "transfer failed");
    }

    

    /**
     * @notice modifier for actions requiring tier 1 delegation
     */
    modifier tierOneDelegation() {
        BIOPTokenV3 token = BIOPTokenV3(tA);
        AccessTiers tiers = AccessTiers(aTA);
        require(tiers.tier1(shas[msg.sender], dBIOP), "insufficent delegate power");
        _;
    }

    /**
     * @notice modifier for actions requiring a tier 2 delegation
     */
    modifier tierTwoDelegation() {
        BIOPTokenV3 token = BIOPTokenV3(tA);
        AccessTiers tiers = AccessTiers(aTA);
        require(tiers.tier2(shas[msg.sender], dBIOP), "insufficent delegate power");
        _;
    }

    /**
     * @notice modifier for actions requiring a tier 3 delegation
     */
    modifier tierThreeDelegation() {
        BIOPTokenV3 token = BIOPTokenV3(tA);
        AccessTiers tiers = AccessTiers(aTA);
        require(tiers.tier3(shas[msg.sender], dBIOP), "insufficent delegate power");
        _;
    }

    /**
     * @notice modifier for actions requiring a tier 4 delegation
     */
    modifier tierFourDelegation() {
        BIOPTokenV3 token = BIOPTokenV3(tA);
        AccessTiers tiers = AccessTiers(aTA);
        require(tiers.tier4(shas[msg.sender], dBIOP), "insufficent delegate power");
        _;
    }


    // 0 tier anyone whose staked can do these two
    /**
     * @notice Send rewards from the proxy to gov and collect a fee
     */
    function sRTG() external {
        require(staked[msg.sender] > 100, "invalid user");
        GovProxy gp = GovProxy(pX);
        uint256 r = gp.transferToGov();
        trg = trg.add(r);
    }

    fallback () external payable {}

     /**
     * @notice add a alt pool
     * @param newPool_ the address of the EBOP20 pool to add
     */
    function addAltPool(address newPool_) external  {
        require(staked[msg.sender] > 100, "invalid user");
        BinaryOptions protocol = BinaryOptions(pA);
        protocol.addAltPool(newPool_);
    }

    /* 
                                                                                              
                                                                                          
                                                                                          
                                                              .-=                         
                      =                               :-=+#%@@@@@                         
               @+@+* -*   -==: ==-+.           -=+#%@@@@@@@@@@@@@                         
                :%    %. -%-=* :%              %@@@@@@@@@@@@@@@@@                         
               .=== .===: -==: ===.            %@@@@%*+=--@@@@@@@                         
                                               --.       .@@@@@@@                         
                                                         .@@@@@@@                         
                                                         .@@@@@@@                         
                                                         .@@@@@@@                         
                                                         .@@@@@@@                         
                                                         .@@@@@@@                         
                                                         .@@@@@@@                         
                      .:    :.                           .@@@@@@@                         
                     -@@#  #@@=                          .@@@@@@@                         
                     +@@#  %@@=                          .@@@@@@@                         
                     *@@*  @@@-                          .@@@@@@@                         
                     #@@+ .@@@:                          .@@@@@@@                         
                 .---@@@*-+@@@=--                        .@@@@@@@                         
                 +@@@@@@@@@@@@@@@.                       .@@@@@@@                         
                    .@@@: =@@@                           .@@@@@@@                         
                    :@@@. +@@#                           .@@@@@@@                         
                 -*##@@@##%@@@##*                        .@@@@@@@                         
                 -##%@@@##@@@%##*                        .@@@@@@@                         
                    +@@#  #@@=                           .@@@@@@@                         
                    *@@*  @@@:                           .@@@@@@@                         
                    *@@+  @@@.                 +**********@@@@@@@**********=              
                    #@@= .@@@                  %@@@@@@@@@@@@@@@@@@@@@@@@@@@%              
                    .--   :=:                  %@@@@@@@@@@@@@@@@@@@@@@@@@@@%              
                                                                                          
                                                                                          
                                                                                          
                                                                                          
                                                                                          
                                                                                          
     */


    /**
     * @notice update the maximum time an option can be created for
     * @param nMT_ the time (in seconds) of maximum possible bet
     */
    function uMXOT(uint256 nMT_) external tierOneDelegation {
        BinaryOptions protocol = BinaryOptions(pA);
        protocol.setMaxT(nMT_);
    }

    /**
     * @notice update the maximum time an option can be created for
     * @param newMinTime_ the time (in seconds) of maximum possible bet
     */
    function uMNOT(uint256 newMinTime_) external tierOneDelegation {
        BinaryOptions protocol = BinaryOptions(pA);
        protocol.setMinT(newMinTime_);
    }

    /* 
                                                                                                  
                                                                                          
                                                    .:-+*##%@@@@@@%#*+=:                  
              :::::   *                        .=+#@@@@@@@@@@@@@@@@@@@@@@%+:              
              @-@=#: =*.  .+=+- :*=+*:        -@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%=            
               .@:    %:  #*--#. **           -@@@@@@@%#+=-::::::-=*@@@@@@@@@@%-          
              :+**- :+*++ .++++ -**+          -@@@#=:                :*@@@@@@@@@=         
                                              .=.                      :%@@@@@@@@=        
                                                                        .@@@@@@@@@.       
                                                                         +@@@@@@@@=       
                                                                         :@@@@@@@@+       
                                                                         -@@@@@@@@=       
                                                                         #@@@@@@@@:       
                                                                        -@@@@@@@@#        
                                                                       :@@@@@@@@%         
                                                                      -@@@@@@@@%.         
                      *#*   -##-                                    .*@@@@@@@@*           
                     =@@@-  @@@%                                   =@@@@@@@@#:            
                     +@@@: .@@@#                                 =%@@@@@@@%-              
                     *@@@. :@@@*                              .+@@@@@@@@#-                
                     #@@@  -@@@=                            .*@@@@@@@@*.                  
                  ...%@@@..=@@@=..                        :#@@@@@@@%=.                    
                :@@@@@@@@@@@@@@@@@@                     -%@@@@@@@%-                       
                 +++*@@@%++%@@@*++=                   :#@@@@@@@#:                         
                    :@@@+  #@@@                     :#@@@@@@@#:                           
                    -@@@=  %@@@                    +@@@@@@@%-                             
                .#%%@@@@@%%@@@@%%%*              -@@@@@@@@*                               
                .#%%@@@@%%%@@@@%%%*             *@@@@@@@@=                                
                    #@@@  .@@@*               .%@@@@@@@@-                                 
                    %@@@  :@@@+              .%@@@@@@@@*                                  
                    @@@%  -@@@=              @@@@@@@@@@#**************************.       
                    @@@#  =@@@-              @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@:       
                    @@@+  =@@@.              @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@:       
                     :.    .:.               @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@:       
                                                                                          
                                                                                          
                                                                                          
                                                                                          

     */

    /**
     * @notice update fee paid to exercisers
     * @param newFee_ the new fee
     */
    function updateExerciserFee(uint256 newFee_) external tierTwoDelegation {
        BinaryOptions protocol = BinaryOptions(pA);
        protocol.updateExerciserFee(newFee_);
    }

    /**
     * @notice update fee paid to expirers
     * @param newFee_ the new fee
     */
    function updateExpirerFee(uint256 newFee_) external tierTwoDelegation {
        BinaryOptions protocol = BinaryOptions(pA);
        protocol.updateExpirerFee(newFee_);
    }

    /**
     * @notice remove a trading pair
     * @param oldPP_ the address of trading pair to be removed
     */
    function removeTradingPair(address oldPP_) external tierTwoDelegation {
        BinaryOptions protocol = BinaryOptions(pA);
        protocol.removePP(oldPP_);
    }

    /**
     * @notice add (or update the RateCalc of existing) trading pair 
     * @param newPP_ the address of trading pair to be added
     * @param newRateCalc_ the address of the rate calc to be used for this pair
     */
    function addUpdateTradingPair(address newPP_, address newRateCalc_) external tierTwoDelegation {
        BinaryOptions protocol = BinaryOptions(pA);
        protocol.addPP(newPP_, newRateCalc_);
    }

   

    /**
     * @notice enable or disable BIOP rewards
     * @param nx_ the new boolean value of rewardsEnabled
     */
    function enableRewards(bool nx_) external tierTwoDelegation {
        BinaryOptions protocol = BinaryOptions(pA);
        protocol.enableRewards(nx_);
    }

    /**
     * @notice update the fee paid to the user whose tx transfers bet fees from GovProxy to the DelegatedGov
     * @param n_ the new fee
     */
    function enableRewards(uint256 n_) external tierTwoDelegation {
        GovProxy gp = GovProxy(pX);
        gp.updateTFee(n_);
    }

    /* 
                                                                                              
                                                                                          
                                                        .:::::::::.                       
                                               .-=*#%@@@@@@@@@@@@@@@@@#*=:                
          -+++++   #.                         %@@@@@@@@@@@@@@@@@@@@@@@@@@@@#=             
          +:+%.%  +%-  .*++*: =%++#:          %@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@+           
            +%     %-  +@==+=  @-             %@@@@#*=-:..      .:-+%@@@@@@@@@@%.         
           ++++. -++++  -+++. ++++            *+-.                   .+@@@@@@@@@%         
                                                                       :@@@@@@@@@-        
                                                                        +@@@@@@@@*        
                                                                        :@@@@@@@@*        
                                                                        :@@@@@@@@+        
                                                                        =@@@@@@@@:        
                                                                       .@@@@@@@@=         
                                                                      :%@@@@@@@=          
                                                                    .*@@@@@@@%:           
                                                                .:+#@@@@@@@#-             
                    .      .                       :======++*#%@@@@@@@@@*-                
                  -@@@-  =@@@:                     +@@@@@@@@@@@@@@@@%=.                   
                  *@@@=  *@@@-                     +@@@@@@@@@@@@@@@@@@@#+-.               
                  #@@@-  #@@@:                     -++++++**#%%@@@@@@@@@@@@%+:            
                  %@@@.  %@@@.                                  .:=#@@@@@@@@@@%-          
                  @@@@   @@@@                                        :*@@@@@@@@@%.        
              :::-@@@@:::@@@@:::                                       .#@@@@@@@@@:       
             #@@@@@@@@@@@@@@@@@@#                                        #@@@@@@@@@.      
             :+++*@@@%++*@@@%+++:                                         @@@@@@@@@+      
                 -@@@*  =@@@+                                             *@@@@@@@@#      
                 =@@@+  +@@@=                                             +@@@@@@@@%      
             =###%@@@%##%@@@%###=                                         *@@@@@@@@#      
             *@@@@@@@@@@@@@@@@@@*                                        .@@@@@@@@@+      
                 #@@@:  %@@@.                                            %@@@@@@@@@.      
                 %@@@.  @@@@                                           .%@@@@@@@@@+       
                 @@@@  .@@@%                 +=:                     :*@@@@@@@@@@+        
                 @@@@  :@@@#                 %@@@@#+=-.          .-+%@@@@@@@@@@@-         
                .@@@%  -@@@*                 %@@@@@@@@@@@@%%%%%@@@@@@@@@@@@@@@=           
                 +%#-   *%#:                 %@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*-             
                                             -+*#%@@@@@@@@@@@@@@@@@@@@%*=.                
                                                    ..:--=======--:.                      
                                                                                          

     */

    /**
     * @notice remove a pool
     * @param oldPool_ the address of the pool to remove
     */
    function removeAltPool(address oldPool_) external tierThreeDelegation {
        BinaryOptions protocol = BinaryOptions(pA);
        protocol.removeAltPool(oldPool_);
    }

    /**
     * @notice update soft lock time for the main pool. 
     * @param newLockSeconds_ the time (in seconds) of the soft pool lock
     */
    function updatePoolLockTime(uint256 newLockSeconds_) external tierThreeDelegation {
        BinaryOptions protocol = BinaryOptions(pA);
        protocol.updatePoolLockSeconds(newLockSeconds_);
    }

    /**
     * @notice update the fee paid by betters when they make a bet
     * @param newBetFee_ the time (in seconds) of the soft pool lock
     */
    function updateBetFee(uint256 newBetFee_) external tierThreeDelegation {
        BinaryOptions protocol = BinaryOptions(pA);
        protocol.updateDevFundBetFee(newBetFee_);
    }

    /* 
                                                                                              
                                                                                          
                                                                                          
                                                                                          
                                                                                          
                       -                                       +######:                   
                %*@*+ =*   -=-  =:==                         .%@@@@@@@-                   
                .:%    @  +#-+= ++ .                        =@@@@@@@@@-                   
                .=== .===. -==:.==-                       .#@@@@@@@@@@-                   
                                                         =@@@@@@%@@@@@-                   
                                                        *@@@@@#.*@@@@@-                   
                                                      -@@@@@@+  *@@@@@-                   
                                                     *@@@@@#.   *@@@@@-                   
                                                   -@@@@@@=     *@@@@@-                   
                                                  *@@@@@%.      *@@@@@-                   
                                                :%@@@@@+        *@@@@@-                   
                       --   .-:                +@@@@@%:         *@@@@@-                   
                      +@@*  @@@.             .%@@@@@+           *@@@@@-                   
                      *@@+  @@@.            =@@@@@%:            *@@@@@-                   
                      #@@= .@@@           .#@@@@@+              *@@@@@-                   
                      %@@- -@@%          =@@@@@%-               *@@@@@-                   
                  :***@@@#*#@@@**=      *@@@@@@#################@@@@@@%######-            
                  =#%%@@@%%@@@@%%+      %@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@+            
                     .@@@  +@@+         %@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@+            
                     -@@@  #@@=         .......................:@@@@@@+......             
                  +@@@@@@@@@@@@@@#                             .@@@@@@-                   
                  .-=#@@%==@@@+==:                             .@@@@@@-                   
                     *@@*  @@@.                                .@@@@@@-                   
                     #@@+ .@@@                                 .@@@@@@-                   
                     %@@= :@@@                                 .@@@@@@-                   
                     *@%. .%@+                                 .@@@@@@-                   
                                                                ******:                   
                                                                                          
     */

     /**
     * @notice change the access tiers contract address used to guard all access tier functions
     * @param newAccessTiers_ the new access tiers contract to use. It should conform to AccessTiers interface
     */
    function updateAccessTiers(address newAccessTiers_) external tierFourDelegation {
        aTA = newAccessTiers_;
    }

    /**
     * @notice change the BinaryOptions 
     * @param newPA_ the new protocol contract to use. It should conform to BinaryOptions interface
     */
    function updateProtocolAddress(address newPA_) external tierFourDelegation {
        pA = newPA_;
    }

    /**
     * @notice prevent new deposits into the pool. Effectivly end the protocol. This cannot be undone.
     */
    function closeStaking() external tierFourDelegation {
        BinaryOptions protocol = BinaryOptions(pA);
        protocol.closeStaking();
    }

}