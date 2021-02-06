const BinaryOptions = artifacts.require("BinaryOptions");
const BIOPTokenV3 = artifacts.require("BIOPTokenV3");
const DelegatedGov = artifacts.require("DelegatedGov");
const GovProxy = artifacts.require("GovProxy");
//const BN = web3.utils.BN;
const DelegatedAccessTiers = artifacts.require("DelegatedAccessTiers");
//fake price provider
const FakePriceProvider = artifacts.require("FakePriceProvider");

const RateCalc = artifacts.require("RateCalc");

const biopSettings = {
  name: "BIOP",
  symbol: "BIOP",
  v2: "0xC961AfDcA1c4A2A17eada10D2e89D052bEf74A85",
  reserveRatio: 500000,
};

const boSettings = {
  name: "Pool Share",
  symbol: "pETH",
  owner: "0xC961AfDcA1c4A2A17eada10D2e89D052bEf74A85",
  priceProviderAddress: "0x9326BFA02ADD2366b30bacB125260Af641031331", //"0x9326BFA02ADD2366b30bacB125260Af641031331" //kovan<- ->mainnet // "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419", //mainnet address
};

const FakePriceSettings = {
  price: 753520000000,
};

//true for testrpc/ganache false for kovan
const testing = true;

module.exports = function (deployer) {
  try {
    if (testing) {
      deployer
        .deploy(FakePriceProvider, FakePriceSettings.price)
        .then((ppInstance) => {
          return deployer.deploy(RateCalc).then((rcInstance) => {
            console.log("deploy 1 complete");
            console.log(ppInstance.address);
            return deployer
              .deploy(
                BIOPTokenV3,
                biopSettings.name,
                biopSettings.symbol,
                biopSettings.v2,
                biopSettings.reserveRatio
              )
              .then((biopInstance) => {
                console.log("deploy 2 complete");
                console.log(biopInstance.address);
                return deployer
                  .deploy(
                    BinaryOptions,
                    boSettings.name,
                    boSettings.symbol,
                    ppInstance.address,
                    biopInstance.address,
                    rcInstance.address
                  )
                  .then(async (boInstance) => {
                    return deployer
                    .deploy(
                      DelegatedAccessTiers,
                    )
                    .then(async (tiersInstance) => {
                      return deployer
                    .deploy(
                      GovProxy,
                    )
                    .then(async (proxyInstance) => {
                    return deployer
                      .deploy(
                        DelegatedGov,
                        boInstance.address,
                        biopInstance.address,
                        tiersInstance.address,
                        proxyInstance.address
                      )
                      .then(async (govInstance) => {
                        await boInstance.transferDevFund(proxyInstance.address);
                        await boInstance.transferOwner(govInstance.address);
                        await proxyInstance.updateDGov(govInstance.address);
                        return await biopInstance.setupBinaryOptions(
                          boInstance.address
                        );
                      });
                    });
                  });
                });
              });
          });
        })
        .catch((e) => {
          console.log("caught");
          console.log(e);
        });
    } else {
      deployer
        .deploy(
          BIOPTokenV3,
          biopSettings.name,
          biopSettings.symbol,
          biopSettings.v2,
          biopSettings.reserveRatio
        )
        .then((biopInstance) => {
          console.log("deploy 1 complete");
          console.log(biopInstance.address);
          return deployer.deploy(RateCalc).then((rcInstance) => {
            return deployer
              .deploy(
                BinaryOptions,
                boSettings.name,
                boSettings.symbol,
                boSettings.priceProviderAddress,
                biopInstance.address,
                rcInstance.address
              )
              .then(async (boInstance) => {
                return deployer
                    .deploy(
                      DelegatedAccessTiers,
                    )
                    .then(async (tiersInstance) => {

                      return deployer
                    .deploy(
                      GovProxy,
                    )
                    .then(async (proxyInstance) => {
                    return deployer
                      .deploy(
                        DelegatedGov,
                        boInstance.address,
                        biopInstance.address,
                        tiersInstance.address,
                        proxyInstance.address
                      )
                      .then(async (govInstance) => {
                        await boInstance.transferDevFund(proxyInstance.address);
                        await boInstance.transferOwner(govInstance.address);
                        await proxyInstance.updateDGov(govInstance.address);
                        return await biopInstance.setupBinaryOptions(
                          boInstance.address
                        );
                      });
                    });
                  });
              });
          });
        });
    }
  } catch (e) {
    console.log(e);
  }
};
