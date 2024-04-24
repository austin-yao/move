module test_package::test_shared{
    use std::string::{Self, String};
    use std::option::{Self, Option, some};
    use std::vector::{Self};
    use std::type_name::{Self, TypeName};
    use sui::object::{Self, ID, UID};
    use sui::clock::{Self, Clock};
    use sui::linked_table::{Self};
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet, into_keys};
    use sui::vec_map::{Self, VecMap, into_keys_values};
    use sui::object_table::{Self, ObjectTable};
    use sui::object_bag::{Self, ObjectBag};
    use sui::address::{Self};
    use sui::dynamic_object_field as ofield;

    use sui::sui::SUI;
    use sui::coin::{Self, Coin, TreasuryCap, join};
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Balance};
    use sui::transfer;

    struct MarginAccountCap has key, store {
        id: UID,
        owner: address
        }

    struct MarginAccount has key, store{
        id: UID,
        owner_cap_id: address,
        balance: u64
    }

    struct Market has key, store{
        id: UID,
        counter : u64,
        margin_account_caps: ObjectTable<address, MarginAccountCap>
    }

    struct Order has key{
        id: UID,
        market_counter: u64,
        quantity: u64
    }

    fun init(ctx: &mut TxContext){

    }

    public fun create_margin_account_cap(market: &mut Market, ctx: &mut TxContext) {
        let id = object::new(ctx);
        let owner = object::uid_to_address(&id);

        let margin_account_cap = MarginAccountCap {
            id: id,
            owner: owner
        };
        object_table::add(&mut market.margin_account_caps, tx_context::sender(ctx), margin_account_cap);
        // transfer::transfer(margin_account_cap, tx_context::sender(ctx));
    }


    public fun create_market(is_shared: bool, ctx: &mut TxContext){
        let market = Market {
            id: object::new(ctx),
            margin_account_caps: object_table::new<address, MarginAccountCap>(ctx),
            counter: 0,
        };
        if (is_shared) {
            transfer::share_object(market);
        }
        else {
            transfer::transfer(market, tx_context::sender(ctx));
        }
    }

    public fun borrow_unmut_margin_account_cap_from_market(market: &Market, ctx: &mut TxContext) : &MarginAccountCap {
        object_table::borrow(&market.margin_account_caps, tx_context::sender(ctx))
    }

    public fun create_margin_account(is_shared: bool, market: &Market, ctx: &mut TxContext){
        // let owner_cap = ;
        let margin_account = MarginAccount {
            id: object::new(ctx),
            owner_cap_id: get_margin_cap_id(borrow_unmut_margin_account_cap_from_market(market, ctx)),
            balance: 1000
        };
        if (is_shared) {
            transfer::share_object(margin_account);
        }
        else {
            transfer::transfer(margin_account, tx_context::sender(ctx));
        }
    }

    public fun place_order(
        market: &mut Market, 
        margin_account: &mut MarginAccount, 
        // margin_account_cap: &MarginAccountCap, 
        quantity: u64, 
        ctx: &mut TxContext
    ){
        let margin_account_cap = borrow_unmut_margin_account_cap_from_market(market, ctx);
        assert!(margin_account.owner_cap_id == get_margin_cap_id(margin_account_cap), 0);
        margin_account.balance = margin_account.balance - 10;
        market.counter = market.counter + 1;
        let order_uid = object::new(ctx);
        transfer::share_object(Order { id: order_uid, market_counter: market.counter, quantity: quantity});
    }

    public fun place_order_quantity(market: &mut Market, quantity: u64, ctx: &mut TxContext){
        // margin_account.balance = margin_account.balance - 10;
        market.counter = market.counter + 1;
        let order_uid = object::new(ctx);
        transfer::share_object(Order { id: order_uid, market_counter: market.counter, quantity: quantity});
    }

    public fun get_margin_cap_id(margin_account_cap: &MarginAccountCap): address {
        margin_account_cap.owner
    }
}