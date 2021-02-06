pragma solidity ^0.6.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./BIOPToken.sol";
import "./ContinuousToken/curves/BancorBondingCurve.sol";
contract BIOPTokenV3 is BancorBondingCurve, ERC20 {
    using SafeMath for uint256;
    address public bO = 0x0000000000000000000000000000000000000000;//binary options
    address payable gov = 0x0000000000000000000000000000000000000000;
    address payable owner;
    address public v2;
    uint256 lEnd;//launch end
    uint256 public tCA = 750000000000000000000000000000;//total claims available
    uint256 public tbca =                 400000000000000000000000000000;//total bonding curve available
                             
    bool public binaryOptionsSet = false;

    uint256 public soldAmount = 0;
    uint256 public buyFee = 2;//10th of percent
    uint256 public sellFee = 0;//10th of percent

    constructor(string memory name_, string memory symbol_, address v2_,  uint32 _reserveRatio) public ERC20(name_, symbol_) BancorBondingCurve(_reserveRatio) {
      owner = msg.sender;
      v2 = v2_;
      lEnd = block.timestamp + 3 days;
      _mint(msg.sender, 100000);
      soldAmount = 100000;
    }


    
    modifier onlyBinaryOptions() {
        require(bO == msg.sender, "Ownable: caller is not the Binary Options Contract");
        _;
    }
    modifier onlyGov() {
        if (gov == 0x0000000000000000000000000000000000000000) {
            require(owner == msg.sender, "Ownable: caller is not the owner");
        } else {
            require(gov == msg.sender, "Ownable: caller is not the owner");
        }
        _;
    }

    /** 
     * @dev a one time function to setup governance
     * @param g_ the new governance address
     */
    function transferGovernance(address payable g_) external onlyGov {
        require(gov == 0x0000000000000000000000000000000000000000);
        require(g_ != 0x0000000000000000000000000000000000000000);
        gov = g_;
    }

    /** 
     * @dev set the fee users pay in ETH to buy BIOP from the bonding curve
     * @param newFee_ the new fee (in tenth percent) for buying on the curve
     */
    function updateBuyFee(uint256 newFee_) external onlyGov {
        require(newFee_ > 0 && newFee_ < 40, "invalid fee");
        buyFee = newFee_;
    }

    /**
     * @dev set the fee users pay in ETH to sell BIOP to the bonding curve
     * @param newFee_ the new fee (in tenth percent) for selling on the curve
     **/
    function updateSellFee(uint256 newFee_) external onlyGov {
        require(newFee_ > 0 && newFee_ < 40, "invalid fee");
        sellFee = newFee_;
    } 

    /**
     * @dev called by the binary options contract to update a users Reward claim
     * @param amount the amount in BIOP to add to this users pending claims
     **/
    function updateEarlyClaim(uint256 amount) external onlyBinaryOptions {
        require(tCA.sub(amount) >= 0, "insufficent claims available");
        if (lEnd < block.timestamp) {
            tCA = tCA.sub(amount);
            _mint(tx.origin, amount.mul(4));
        } else {
            tCA.sub(amount);
            _mint(tx.origin, amount);
        }
    }
     /**
     * @notice one time function used at deployment to configure the connected binary options contract
     * @param options_ the address of the binary options contract
     */
    function setupBinaryOptions(address payable options_) external {
        require(binaryOptionsSet != true, "binary options is already set");
        bO = options_;
        binaryOptionsSet = true;
    }

    /**
     * @dev one time swap of v2 to v3 tokens
     * @notice all v2 tokens will be swapped to v3. This cannot be undone
     */
    function swapv2v3() external {
        BIOPToken b2 = BIOPToken(v2);
        uint256 balance = b2.balanceOf(msg.sender);
        require(balance >= 0, "insufficent biopv2 balance");
        require(b2.transferFrom(msg.sender, address(this), balance), "staking failed");
        _mint(msg.sender, balance);
    }


    


    //bonding curve functions

     /**
    * @dev method that returns BIOP amount sold by curve
    */   
    function continuousSupply() public override view returns (uint) {
        return soldAmount;
    }

    /**
    * @dev method that returns curves ETH (reserve) balance
    */    
    function reserveBalance() public override view returns (uint) {
        return address(this).balance;
    }

    /**
     * @notice purchase BIOP from the bonding curve. 
     the amount you get is based on the amount in the pool and the amount of eth u send.
     */
     function buy() public payable {
        uint256 purchaseAmount = msg.value;
        
         if (buyFee > 0) {
            uint256 fee = purchaseAmount.div(buyFee).div(100);
            if (gov == 0x0000000000000000000000000000000000000000) {
                require(owner.send(fee), "buy fee transfer failed");
            } else {
                require(gov.send(fee), "buy fee transfer failed");
            }
            purchaseAmount = purchaseAmount.sub(fee);
        } 
        uint rewardAmount = getContinuousMintReward(purchaseAmount);
        require(soldAmount.add(rewardAmount) <= tbca, "maximum curve minted");
        
        _mint(msg.sender, rewardAmount);
        soldAmount = soldAmount.add(rewardAmount);
    }

    
     /**
     * @notice sell BIOP to the bonding curve
     * @param amount the amount of BIOP to sell
     */
     function sell(uint256 amount) public returns (uint256){
        require(balanceOf(msg.sender) >= amount, "insufficent BIOP balance");

        uint256 ethToSend = getContinuousBurnRefund(amount);
        if (sellFee > 0) {
            uint256 fee = ethToSend.div(buyFee).div(100);
            if (gov == 0x0000000000000000000000000000000000000000) {
                require(owner.send(fee), "buy fee transfer failed");
            } else {
                require(gov.send(fee), "buy fee transfer failed");
            }
            ethToSend = ethToSend.sub(fee);
        }
        soldAmount = soldAmount.sub(amount);
        _burn(msg.sender, amount);
        require(msg.sender.send(ethToSend), "transfer failed");
        return ethToSend;
        }
}
