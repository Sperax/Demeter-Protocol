const { providers, Contract, utils } = require("ethers")
const { hexZeroPad } = require("ethers/lib/utils");
const rpc = "https://arbitrum-mainnet.infura.io/v3/d8058e7659184563bc4dbbfc5e9c407c"
const farmABI = require("../build/contracts/Demeter_UniV3Farm_v2.json").abi;
const factoryABI = require("../build/contracts/FarmFactory.json").abi;


const user = "0x0000000000000000000000000000000000000000"
const factoryAddr = "0xC4fb09E0CD212367642974F6bA81D8e23780A659";
const provider = new providers.JsonRpcProvider(rpc)
const factory = new Contract(factoryAddr, factoryABI, provider);

let parser = new utils.Interface(farmABI);

async function getFarmDeployer(farm) {
    const farmObj = new Contract(farm, farmABI, provider);
    const filter = {
        address: farm,
        topics: [
            utils.id("OwnershipTransferred(address,address)"),
            hexZeroPad(user, 32),
        ]
    }
    let events = await farmObj.queryFilter(filter, 27001371);
    let res = {};
    for(let i = 0; i < events.length; i++) {
        let ev = events[i];
        let args = parser.parseLog({data: ev.data, topics: ev.topics});
        res[ev.address] = args.args[1]
    }
    return res;
}

async function fetch_events(){
    const farms = await factory.getFarmList();
    let data = [];
    for(let i = 0; i < farms.length; i++) {
        console.log(`${i}. Processing Farm: ${farms[i]}`);
        let farmData = await getFarmDeployer(farms[i]);
        data.push(farmData);
    }
    return data;
}

fetch_events().then(console.log)