import "dotenv/config"

import { Ed25519Keypair } from "@mysten/sui.js/keypairs/ed25519"
// import { bcs } from '@mysten/bcs';
import { SuiClient, SuiObjectRef, SuiTransactionBlockResponse } from "@mysten/sui.js/client"
import { is, normalizeSuiAddress, fromB64 } from "@mysten/sui.js/utils"
import { execSync } from "child_process"
import { TransactionBlock } from "@mysten/sui.js/transactions"
import path from "path"
import { writeFileSync } from "fs"
import { fileURLToPath } from "url"
import { split_gas, find_object_id_of_type, find_object_ids_of_type } from "./utils"

const deploy = true;

const formatDecimals = (decimals: string) => {
    return (parseInt(decimals) / 1_000_000_000).toFixed(5).toLocaleLowerCase()
}

const root_dir = path.dirname(fileURLToPath(import.meta.url))
const output_dirs = [
    path.join(root_dir, "output/")
]

const mnemonic = process.env.DEPLOYER_MNEMONIC
const mnemonic_trader2 = process.env.TRADER2_MNEMONIC
if (!mnemonic) {
    console.log('Requires DEPLOYER_MNEUMONIC set in .env');
    process.exit(1);
}

const rpc_endpoint = process.env.RPC_ENDPOINT
if (!rpc_endpoint) {
    console.log('Requires RPC_ENDPOINT set in .env');
    process.exit(1);
}

const client = new SuiClient({ url: rpc_endpoint })

const from_private_key = (private_key: string) => {
    const raw = fromB64(private_key);
    if (raw[0] !== 0) {
        throw new Error('invalid key');
    }
    const imported = Ed25519Keypair.fromSecretKey(raw.slice(1))
    return imported
}

// setup wallet for deployer
// const keypair = from_private_key(mnemonic)
const keypair = Ed25519Keypair.deriveKeypair(mnemonic)
const address_deployer = keypair.toSuiAddress()
console.log(`Deployer address determined to be: ${address_deployer}`)

const balance = await client.getBalance({ owner: address_deployer })
console.log(`Deployer address found to have ${formatDecimals(balance.totalBalance)} Sui`)


// setup wallet for trader2
// const keypair_trader2 = from_private_key(mnemonic_trader2)
const keypair_trader2 = Ed25519Keypair.deriveKeypair(mnemonic_trader2)
const address_trader2 = keypair_trader2.toSuiAddress()
console.log(`Trader2 address determined to be: ${address_trader2}`)

const balance_trader2 = await client.getBalance({ owner: address_trader2 })
console.log(`Trader2 address found to have ${formatDecimals(balance_trader2.totalBalance)} Sui`)

var deployed_objects: any = {}

if (deploy){
    // ================ FOR DEPLOYMENT ================
    // build contracts
    console.log("Building contracts...")
    const { modules, dependencies } = JSON.parse(
        execSync(
            `cd ../contracts/test_package; sui move build --dump-bytecode-as-base64`,
            { encoding: "utf-8" }
        )
    )

    const deploy_tx = new TransactionBlock()
    const [upgrade_cap] = deploy_tx.publish({
        modules, dependencies
    })
    deploy_tx.transferObjects([upgrade_cap], deploy_tx.pure(address_deployer))

    console.log("Publishing module...")
    const result = await client.signAndExecuteTransactionBlock({
        transactionBlock: deploy_tx,
        options: {
            showEffects: true,
            showObjectChanges: true,
            showBalanceChanges: true,
            showEvents: true
        },
        signer: keypair
    })

    console.log(`SUI balance change after module publish: ${formatDecimals(result.balanceChanges?.[0].amount)}`)

    const package_change = result.objectChanges.find(change => change.type == "published")
    const package_id = package_change.type === "published" ? package_change.packageId : undefined
    if (!package_id) {
        console.log("Failed to get package id")
        process.exit(0)
    }

    deployed_objects = {
        types: {
            MARGIN: `${package_id}::test_shared::MarginAccount`,
            MARKET: `${package_id}::test_shared::Market`,
        },
        PACKAGE: package_id,
        ADDRESS_DEPLOYER: address_deployer,
    }


    output_dirs.forEach(output_dir => {
        const output_file = path.join(output_dir, "deployed_objects.json")
        console.log(`Writing deployed_objects to ${output_file}`)
        writeFileSync(
            output_file,
            JSON.stringify(deployed_objects, null, 4)
        )
    })
}
else {
    deployed_objects = JSON.parse(
        execSync(
            `cat ${path.join(path.join(root_dir, "scripts/simulation"), "deployed_objects.json")}`,
            { encoding: "utf-8" }
        )
    )
}
// ============= Function ==============


const make_order = async (tx3: TransactionBlock, gas_object_id: string, deployed_objects: any, trader_index: number) => {
    console.log(`Placing order from ${trader_index ===0 ? "deployer": "trader2"}`)
    const from_deployer = trader_index === 0 ? true: false
    // const tx3 = new TransactionBlock();
    tx3.moveCall({
        target: `${deployed_objects.PACKAGE}::test_shared::place_order`,
        arguments: [
            tx3.object(deployed_objects.MARKET),
            tx3.object(trader_index === 0 ? deployed_objects.MARGIN: deployed_objects.MARGIN_TRADER2),
            // tx3.object(deployed_objects.MARGIN),
            // tx3.object(from_deployer? deployed_objects.MARGINACCOUNTCAP_DEPLOYER: deployed_objects.MARGINACCOUNTCAP_TRADER2),
            // tx3.object(from_deployer? deployed_objects.MARGIN: deployed_objects.MARGIN_TRADER2),
            tx3.pure(Math.floor( Math.random() * 7 )), 
            // tx3.pure(1), 
        ],

    })
    const object = await client.getObject({ id: gas_object_id })
    tx3.setGasPayment([{
        objectId: gas_object_id, 
        version: String(object?.data?.version),
        digest: String(object?.data?.digest),
    }]);

    const startTime = new Date().getTime();
    client.signAndExecuteTransactionBlock({
        transactionBlock: tx3,
        options: {
            showEffects: true,
            showObjectChanges: true,
            showBalanceChanges: true,
            showEvents: true
        },
        signer: from_deployer? keypair: keypair_trader2,
    })
    .then(data => {
        const endTime = new Date().getTime();
        const elapsedTime = endTime - startTime;
        console.log(`Elapsed time: ${elapsedTime}ms`);
    });
    return tx3
}


const test_shared = async (deployed_objects: any, market_is_shared: boolean, margin_is_shared: boolean, is_ptb: boolean, wait_ms: number) => {
    
    console.log("=====================================")
    console.log(`Testing shared market: ${market_is_shared} and shared margin: ${margin_is_shared}`)
    // Create clearinghouse
    console.log("Creating the market...")
    // Create the clearinghouse
    const tx1 = new TransactionBlock();
    tx1.moveCall({
        target: `${deployed_objects.PACKAGE}::test_shared::create_market`,
        arguments: [
            tx1.pure(market_is_shared? true: false)
        ],
        // typeArguments: [deployed_objects.types.IGUSD, deployed_objects.types.MARGINUSDC, deployed_objects.types.REALUSDC]
    });

    const create_market_result = await client.signAndExecuteTransactionBlock({
        transactionBlock: tx1,
        options: {
            showEffects: true,
            showObjectChanges: true,
            showBalanceChanges: true,
            showEvents: true
        },
        signer: keypair
    });

    Object.assign(deployed_objects, {
        MARKET: find_object_id_of_type(
            create_market_result, 
            `${deployed_objects.PACKAGE}::test_shared::Market`
        ),
    })


    // create margin account cap
    console.log("Creating the margin account cap...")
    const txb = new TransactionBlock();
    txb.moveCall({
        target: `${deployed_objects.PACKAGE}::test_shared::create_margin_account_cap`,
        arguments: [txb.object(deployed_objects.MARKET)],
        // typeArguments: [deployed_objects.types.IGUSD, deployed_objects.types.MARGINUSDC, deployed_objects.types.REALUSDC]
    });

    const create_cap_result = await client.signAndExecuteTransactionBlock({
        transactionBlock: txb,
        options: {
            showEffects: true,
            showObjectChanges: true,
            showBalanceChanges: true,
            showEvents: true
        },
        signer: keypair
    });

    Object.assign(deployed_objects, {
        MARGINACCOUNTCAP_DEPLOYER: find_object_id_of_type(
            create_cap_result, 
            `${deployed_objects.PACKAGE}::test_shared::MarginAccountCap`
        ),
    })

    // create margin account cap for trader 2
    console.log("Creating the margin account cap for trader 2...")
    const txb2 = new TransactionBlock();
    txb2.moveCall({
        target: `${deployed_objects.PACKAGE}::test_shared::create_margin_account_cap`,
        arguments: [txb2.object(deployed_objects.MARKET)],
        // typeArguments: [deployed_objects.types.IGUSD, deployed_objects.types.MARGINUSDC, deployed_objects.types.REALUSDC]
    });

    const create_cap_result2 = await client.signAndExecuteTransactionBlock({
        transactionBlock: txb2,
        options: {
            showEffects: true,
            showObjectChanges: true,
            showBalanceChanges: true,
            showEvents: true
        },
        signer: keypair_trader2
    });

    Object.assign(deployed_objects, {
        MARGINACCOUNTCAP_TRADER2: find_object_id_of_type(
            create_cap_result2, 
            `${deployed_objects.PACKAGE}::test_shared::MarginAccountCap`
        ),
    })



    // Create margin
    console.log("Creating the margin...")
    // Create the clearinghouse
    const tx2 = new TransactionBlock();
    tx2.moveCall({
        target: `${deployed_objects.PACKAGE}::test_shared::create_margin_account`,
        arguments: [
            tx2.pure(margin_is_shared? true: false),
            tx2.object(deployed_objects.MARKET)
        ],
        // typeArguments: [deployed_objects.types.IGUSD, deployed_objects.types.MARGINUSDC, deployed_objects.types.REALUSDC]
    });

    const create_margin_result = await client.signAndExecuteTransactionBlock({
        transactionBlock: tx2,
        options: {
            showEffects: true,
            showObjectChanges: true,
            showBalanceChanges: true,
            showEvents: true
        },
        signer: keypair
    });

    Object.assign(deployed_objects, {
        MARGIN: find_object_id_of_type(
            create_margin_result, 
            `${deployed_objects.PACKAGE}::test_shared::MarginAccount`
        ),
    })
    console.log(`Deployer's margin: ${deployed_objects.MARGIN}`)


    // Create margin
    console.log("Creating the margin for trader2...")
    // Create the clearinghouse
    const tx3 = new TransactionBlock();
    tx3.moveCall({
        target: `${deployed_objects.PACKAGE}::test_shared::create_margin_account`,
        arguments: [
            tx3.pure(margin_is_shared? true: false),
            tx3.object(deployed_objects.MARKET),
            // tx3.object(deployed_objects.MARGINACCOUNTCAP_TRADER2)
        ],
        // typeArguments: [deployed_objects.types.IGUSD, deployed_objects.types.MARGINUSDC, deployed_objects.types.REALUSDC]
    });

    const create_margin_result2 = await client.signAndExecuteTransactionBlock({
        transactionBlock: tx3,
        options: {
            showEffects: true,
            showObjectChanges: true,
            showBalanceChanges: true,
            showEvents: true
        },
        signer: keypair_trader2
    });

    Object.assign(deployed_objects, {
        MARGIN_TRADER2: find_object_id_of_type(
            create_margin_result2, 
            `${deployed_objects.PACKAGE}::test_shared::MarginAccount`
        ),
    })
    console.log(`Trader2's margin: ${deployed_objects.MARGIN_TRADER2}`)

    // place orders
    
    console.log("Placing orders...")

    if (is_ptb){
        // let tx4 = new TransactionBlock();
        try{
            // tx4 = make_order(tx4, deployed_objects, true)
            // await new Promise(r => setTimeout(r, wait_ms));
            // tx4 = make_order(tx4, deployed_objects, true)
            // await new Promise(r => setTimeout(r, wait_ms));
            // tx4 = make_order(tx4, deployed_objects, true)
            // await new Promise(r => setTimeout(r, wait_ms));
            // tx4 = make_order(tx4, deployed_objects, true)
            // await new Promise(r => setTimeout(r, wait_ms));
            // tx4 = make_order(tx4, deployed_objects, true)
            // await new Promise(r => setTimeout(r, wait_ms));
            // tx4 = make_order(tx4, deployed_objects, true)
            // await new Promise(r => setTimeout(r, wait_ms));


            // const make_order_result4 = await make_order(deployed_objects, true)
            // console.log(make_order_result4)
            // await new Promise(r => setTimeout(r, wait_ms));
            // const make_order_result5 = await make_order(deployed_objects, true)
            // console.log(make_order_result5)
            // await new Promise(r => setTimeout(r, wait_ms));
            // const make_order_result6 = await make_order(deployed_objects, true)
            // console.log(make_order_result6)
            // await new Promise(r => setTimeout(r, wait_ms));
        }
        catch(e){
            console.log(e)
        }
    }else{
        try{
            const gas_amount = 6_000_000
            const trader_indices = [0, 1]
            const gas_objects = await split_gas(client, [keypair, keypair_trader2], trader_indices, gas_amount)
            // const gas_objects_trader2 = await split_gas(client, keypair_trader2, gas_amount, false)
            gas_objects.forEach(async (gas_object, index) => {
                make_order(new TransactionBlock(), gas_objects[index], deployed_objects, trader_indices[index])
                await new Promise(r => setTimeout(r, wait_ms));
            })
        }
        catch (e){
            console.log(e)
        }
    }
}

const start = new Date().getTime();

await test_shared(deployed_objects, true, false, false, 50)
// await new Promise(r => setTimeout(r, 5000));
// await test_shared(true, false, 10)
// await new Promise(r => setTimeout(r, 5000));
// await test_shared(false, true, 2000)
// await new Promise(r => setTimeout(r, 5000));
// test_shared(false, false, 500)

let elapsed = new Date().getTime() - start;
console.log(`Time elapsed: ${elapsed}ms`)
