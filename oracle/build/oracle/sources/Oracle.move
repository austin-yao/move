module 0x2::Oracle {
    // use std::signer;

    // use std::vector;
    use std::string::String;
    use std::vector;
    use sui::tx_context::TxContext;
    use sui::object::{Self, ID, UID};
    use sui::coin::{Self, Coin, TreasuryCap, join};
    use sui::random;

    // use sui::object::{Self, ID, Info};
    // use sui::tx_context::{Self, TxContext};
    // use sui::transfer::{Self};

    struct Proposal has store, key {
        id: UID,
        proposer: address,
        oracleId: u64,
        // 0 or  1
        response: bool,
    }

    struct Query has store, key {
        id: UID,
        // p1: address,
        // p2: address,
        betId: u64,
        question: String, 
        validators: vector<Proposal>
    }

    // cannot store anything in the global. 

    // for the address of the contract (?) if it exists, we store a vector of oracles
    // when we need to do operations on the oracles, we retrieve it from the global storage.

    // temporarily returns a new Query
    public fun receiveQuery(betId: u64, question: String, ctx: &mut TxContext): Query {
        // access the vector of queries
        let newQuery = Query {
            id: object::new(ctx),
            betId: betId,
            question: question,
            validators: vector::empty<Proposal>(),
        };
        // add it to the vector of queries
        newQuery
    }

    // should also take in coin, will add in later
    // TODO: create a new coin type
    public fun requestValidate(ctx: &mut TxContext, coin: Coin<Proposal>): Coin<Proposal> {
        coin
    }

}