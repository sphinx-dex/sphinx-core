%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import unsigned_div_rem
from starkware.starknet.common.syscalls import get_caller_address
from starkware.starknet.common.syscalls import get_block_timestamp
from src.tree.limits import Limit, limits, print_limit_order, print_dfs_in_order
from src.tree.orders import Order, print_list, print_order
from starkware.cairo.common.alloc import alloc

struct Market {
    id : felt,
    bid_tree_id : felt,
    ask_tree_id : felt,
    lowest_ask : felt,
    highest_bid : felt,
    base_asset : felt,
    quote_asset : felt,
    controller : felt,
}

@contract_interface
namespace IOrdersContract {
    // Getter for head ID and tail ID.
    func get_head_and_tail(limit_id : felt) -> (head_id : felt, tail_id : felt) {
    }
    // Getter for list length.
    func get_length(limit_id : felt) -> (len : felt) {
    }
    // Getter for particular order.
    func get_order(id : felt) -> (order : Order) {
    }
    // Insert new order to the list.
    func push(is_buy : felt, price : felt, amount : felt, dt : felt, owner : felt, limit_id : felt) -> (new_order : Order) {
    }
    // Remove order from head of list
    func shift(limit_id : felt) -> (del : Order) {
    } 
    // Retrieve order at particular position in the list.
    func get(limit_id : felt, idx : felt) -> (order : Order) {
    }
    // Update order at particular position in the list.
    func set(id : felt, is_buy : felt, price : felt, amount : felt, filled : felt, dt : felt, owner : felt) -> 
        (success : felt) {
    }
    // Update filled amount of order.
    func set_filled(id : felt, filled : felt) -> (success : felt) {  
    }
    // Remove value at particular position in the list.
    func remove(limit_id : felt, idx : felt) -> (del : Order) {
    }
}

@contract_interface
namespace ILimitsContract {
    // Getter for limit price
    func get_limit(limit_id : felt) -> (limit : Limit) {
    }
    // Getter for lowest limit price within tree
    func get_min(tree_id : felt) -> (min : Limit) {
    }
    // Getter for highest limit price within tree
    func get_max(tree_id : felt) -> (max : Limit) {
    }
    // Insert new limit price into BST.
    func insert(price : felt, tree_id : felt, market_id : felt) -> (new_limit : Limit) {
    }
    // Find a limit price in binary search tree.
    func find(price : felt, tree_id : felt) -> (limit : Limit, parent : Limit) {    
    }
    // Deletes limit price from BST
    func delete(price : felt, tree_id : felt, market_id : felt) -> (del : Limit) {
    }
    // Setter function to update details of a limit price.
    func update(limit_id : felt, total_vol : felt, order_len : felt, order_head : felt, order_tail : felt ) -> (success : felt) {
    }   
}

@contract_interface
namespace IBalancesContract {
    // Getter for user balances
    func get_balance(user : felt, asset : felt, in_account : felt) -> (amount : felt) {
    }
    // Setter for user balances
    func set_balance(user : felt, asset : felt, in_account : felt, new_amount : felt) {
    }
    // Transfer balance from one user to another.
    func transfer_balance(sender : felt, recipient : felt, asset : felt, amount : felt) -> (success : felt) {
    }
    // Transfer account balance to order balance.
    func transfer_to_order(user : felt, asset : felt, amount : felt) -> (success : felt) {
    }
    // Transfer order balance to account balance.
    func transfer_from_order(user : felt, asset : felt, amount : felt) -> (success : felt) {
    }
    // Fill an open order.
    func fill_order(buyer : felt, seller : felt, base_asset : felt, quote_asset : felt, amount : felt, price : felt) -> (success : felt) {
    }
}

// Stores active markets.
@storage_var
func markets(id : felt) -> (market : Market) {
}

// Stores on-chain mapping of asset addresses to market id.
@storage_var
func market_ids(base_asset : felt, quote_asset : felt) -> (market_id : felt) {
}

// Stores pointers to bid and ask limit trees.
@storage_var
func trees(id : felt) -> (root_id : felt) {
}

// Stores latest market id.
@storage_var
func curr_market_id() -> (id : felt) {
}

// Stores latest tree id.
@storage_var
func curr_tree_id() -> (id : felt) {
}

// Emit create market event.
@event
func log_create_market(id : felt, bid_tree_id : felt, ask_tree_id : felt, lowest_ask : felt, highest_bid : felt, base_asset : felt, quote_asset : felt, controller : felt) {
}

// Emit create new bid.
@event
func log_create_bid(id : felt, limit_id : felt, market_id : felt, dt : felt, owner : felt, base_asset : felt, quote_asset : felt, price : felt, amount : felt) {
}

// Emit create new ask.
@event
func log_create_ask(id : felt, limit_id : felt, market_id : felt, dt : felt, owner : felt, base_asset : felt, quote_asset : felt, price : felt, amount : felt) {
}

// Emit buy order filled.
@event
func log_buy_filled(id : felt, limit_id : felt, market_id : felt, dt : felt, owner : felt, seller : felt, base_asset : felt, quote_asset : felt, price : felt, amount : felt, total_filled : felt) {
}

// Emit offer taken by buy order.
@event
func log_offer_taken(id : felt, limit_id : felt, market_id : felt, dt : felt, owner : felt, buyer : felt, base_asset : felt, quote_asset : felt, price : felt, amount : felt, total_filled : felt) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} () {
    curr_market_id.write(1);
    curr_tree_id.write(1);
    return ();
}

// Create a new market for exchanging between two assets.
// @param base_asset : felt representation of ERC20 base asset contract address
// @param quote_asset : felt representation of ERC20 quote asset contract address
// @param controller : felt representation of account that controls the market
func create_market{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    base_asset : felt, quote_asset : felt) -> (new_market : Market
) {
    alloc_locals;
    
    let (market_id) = curr_market_id.read();
    let (tree_id) = curr_tree_id.read();
    let (caller) = get_caller_address();
    
    tempvar new_market: Market* = new Market(
        id=market_id, bid_tree_id=tree_id, ask_tree_id=tree_id+1, lowest_ask=0, highest_bid=0, 
        base_asset=base_asset, quote_asset=quote_asset, controller=caller
    );
    markets.write(market_id, [new_market]);

    curr_market_id.write(market_id + 1);
    curr_tree_id.write(tree_id + 2);
    market_ids.write(base_asset, quote_asset, market_id + 1);

    log_create_market.emit(
        id=market_id, bid_tree_id=tree_id, ask_tree_id=tree_id+1, lowest_ask=0, highest_bid=0, 
        base_asset=base_asset, quote_asset=quote_asset, controller=caller
    );

    return (new_market=[new_market]);
}

// Update inside quote of market.
func update_inside_quote{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    market_id : felt, lowest_ask : felt, highest_bid : felt) -> (success : felt
) {
    let (market) = markets.read(market_id);
    if (market.id == 0) {
        return (success=0);
    }
    tempvar new_market: Market* = new Market(
        id=market_id, bid_tree_id=market.bid_tree_id, ask_tree_id=market.ask_tree_id, lowest_ask=lowest_ask, 
        highest_bid=highest_bid, base_asset=market.base_asset, quote_asset=market.quote_asset, controller=market.controller
    );
    markets.write(market_id, [new_market]);
    return (success=1);
}

// Submit a new bid (limit buy order) to a given market.
// @param orders_addr : deployed address of IOrdersContract [TEMPORARY - FOR TESTING ONLY]
// @param limits_addr : deployed address of ILimitsContract [TEMPORARY - FOR TESTING ONLY]
// @param balances_addr : deployed address of IBalancesContract [TEMPORARY - FOR TESTING ONLY]
// @param market_id : ID of market
// @param price : limit price of order
// @param amount : order size in number of tokens of quote asset
// @return success : 1 if successfully created bid, 0 otherwise
func create_bid{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    orders_addr : felt, limits_addr : felt, balances_addr : felt, market_id : felt, price : felt, amount : felt
) -> (success : felt) {
    alloc_locals;

    let (market) = markets.read(market_id);
    let (limit, _) = ILimitsContract.find(limits_addr, price, market.bid_tree_id);
    let (lowest_ask) = IOrdersContract.get_order(orders_addr, market.lowest_ask);

    %{ print("[markets.cairo] create_bid > market.id: {}".format(ids.market.id)) %}
    if (market.id == 0) {
        with_attr error_message("Market does not exist") {
            assert 0 = 1;
        }
        return (success=0);
    }

    // If ask exists and price greater than lowest ask, place market buy
    %{ print("[markets.cairo] create_bid > lowest_ask.id: {}".format(ids.lowest_ask.id)) %}
    if (lowest_ask.id == 0) {
        handle_revoked_refs();
    } else {        
        let is_market_order = is_le(lowest_ask.price, price);
        %{ print("[markets.cairo] create_bid > is_market_order: {}".format(ids.is_market_order)) %}
        handle_revoked_refs();
        if (is_market_order == 1) {
            let (buy_order_success) = buy(orders_addr, limits_addr, balances_addr, market.id, price, amount);
            assert buy_order_success = 1;
            handle_revoked_refs();
            return (success=1);
        } else {
            handle_revoked_refs();
        }
    }
    
    // Otherwise, place limit order
    %{ print("[markets.cairo] create_bid > limit.id: {}".format(ids.limit.id)) %}
    if (limit.id == 0) {
        // Limit tree doesn't exist yet, insert new limit tree
        let (new_limit) = ILimitsContract.insert(limits_addr, price, market.bid_tree_id, market.id);
        let create_limit_success = is_le(1, new_limit.id);
        assert create_limit_success = 1;
        let (create_bid_success) = create_bid_helper(orders_addr, limits_addr, balances_addr, market, new_limit, price, amount);
        assert create_bid_success = 1;
        handle_revoked_refs();
    } else {
        // Add order to limit tree
        let (create_bid_success) = create_bid_helper(orders_addr, limits_addr, balances_addr, market, limit, price, amount);
        assert create_bid_success = 1;
        handle_revoked_refs();
    }
    
    return (success=1);
}

// Helper function for creating a new bid (limit buy order).
// @param orders_addr : deployed address of IOrdersContract [TEMPORARY - FOR TESTING ONLY]
// @param limits_addr : deployed address of ILimitsContract [TEMPORARY - FOR TESTING ONLY]
// @param balances_addr : deployed address of IBalancesContract [TEMPORARY - FOR TESTING ONLY]
// @param market : market to which bid is being submitted
// @param limit : limit tree to which bid is being submitted
// @param price : limit price of order
// @param amount : order size in number of tokens of quote asset
// @return success : 1 if successfully created bid, 0 otherwise
func create_bid_helper{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    orders_addr : felt, limits_addr : felt, balances_addr : felt, market : Market, limit : Limit, 
    price : felt, amount : felt
) -> (success : felt) {
    alloc_locals;
    let (caller) = get_caller_address();
    let (account_balance) = IBalancesContract.get_balance(balances_addr, caller, market.base_asset, 1);
    let balance_sufficient = is_le(amount, account_balance);
    %{ print("[markets.cairo] create_bid_helper > amount: {}, account_balance: {}, balance_sufficient: {}".format(ids.amount, ids.account_balance, ids.balance_sufficient)) %}
    if (balance_sufficient == 0) {
        handle_revoked_refs();
        return (success=0);
    } else {
        handle_revoked_refs();
    }

    let (dt) = get_block_timestamp();
    let (new_order) = IOrdersContract.push(orders_addr, 1, price, amount, dt, caller, limit.id);
    let (new_head, new_tail) = IOrdersContract.get_head_and_tail(orders_addr, limit.id);
    let (update_limit_success) = ILimitsContract.update(limits_addr, limit.id, limit.total_vol + amount, limit.order_len + 1, new_head, new_tail);
    assert update_limit_success = 1;

    let (highest_bid) = IOrdersContract.get_order(orders_addr, market.highest_bid);
    let highest_bid_exists = is_le(1, highest_bid.id); 
    let is_not_highest_bid = is_le(price, highest_bid.price - 1);
    %{ print("[markets.cairo] create_bid_helper > highest_bid_exists: {}, is_not_highest_bid: {}".format(ids.highest_bid_exists, ids.is_not_highest_bid)) %}
    if (is_not_highest_bid + highest_bid_exists == 2) {
        handle_revoked_refs();
    } else {
        let (update_market_success) = update_inside_quote(market.id, market.lowest_ask, new_order.id);
        assert update_market_success = 1;
        handle_revoked_refs();
    }
    let (update_balance_success) = IBalancesContract.transfer_to_order(balances_addr, caller, market.base_asset, amount);
    assert update_balance_success = 1;

    log_create_bid.emit(id=new_order.id, limit_id=limit.id, market_id=market.id, dt=dt, owner=caller, base_asset=market.base_asset, quote_asset=market.quote_asset, price=price, amount=amount);

    return (success=1);
}

// Submit a new ask (limit sell order) to a given market.
// @param orders_addr : deployed address of IOrdersContract [TEMPORARY - FOR TESTING ONLY]
// @param limits_addr : deployed address of ILimitsContract [TEMPORARY - FOR TESTING ONLY]
// @param balances_addr : deployed address of IBalancesContract [TEMPORARY - FOR TESTING ONLY]
// @param market_id : ID of market
// @param price : limit price of order
// @param amount : order size in number of tokens of quote asset
// @return success : 1 if successfully created ask, 0 otherwise
func create_ask{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    orders_addr : felt, limits_addr : felt, balances_addr : felt, market_id : felt, price : felt, amount : felt
) -> (success : felt) {
    alloc_locals;

    let (market) = markets.read(market_id);
    let (limit, _) = ILimitsContract.find(limits_addr, price, market.ask_tree_id);
    let (highest_bid) = IOrdersContract.get_order(orders_addr, market.highest_bid);

    %{ print("[markets.cairo] create_ask > market.id: {}".format(ids.market.id)) %}
    if (market.id == 0) {
        with_attr error_message("Market does not exist") {
            assert 0 = 1;
        }
        return (success=0);
    }

    // If bid exists and price lower than highest bid, place market sell
    %{ print("[markets.cairo] create_ask > highest_bid.id: {}".format(ids.highest_bid.id)) %}
    if (highest_bid.id == 1) {
        let is_market_order = is_le(price, highest_bid.price);
        %{ print("[markets.cairo] create_ask > is_market_order: {}".format(ids.is_market_order)) %}
        handle_revoked_refs();
        if (is_market_order == 1) {
            // let (buy_order_success) = buy(orders_addr, limits_addr, balances_addr, market.id, price, amount);
            // assert buy_order_success = 1;
            return (success=1);
            handle_revoked_refs();
        } else {
            handle_revoked_refs();
        }
    } else {
        handle_revoked_refs();
    }

    // Otherwise, place limit sell order
    %{ print("[markets.cairo] create_ask > limit.id: {}".format(ids.limit.id)) %}
    if (limit.id == 0) {
        // Limit tree doesn't exist yet, insert new limit tree
        let (new_limit) = ILimitsContract.insert(limits_addr, price, market.ask_tree_id, market.id);
        let create_limit_success = is_le(1, new_limit.id);
        assert create_limit_success = 1;
        let (create_ask_success) = create_ask_helper(orders_addr, limits_addr, balances_addr, market, new_limit, price, amount);
        assert create_ask_success = 1;
        handle_revoked_refs();
    } else {
        // Add order to limit tree
        let (create_ask_success) = create_ask_helper(orders_addr, limits_addr, balances_addr, market, limit, price, amount);
        assert create_ask_success = 1;
        handle_revoked_refs();
    }
    
    return (success=1);
}

// Helper function for creating a new ask (limit sell order).
// @param orders_addr : deployed address of IOrdersContract [TEMPORARY - FOR TESTING ONLY]
// @param limits_addr : deployed address of ILimitsContract [TEMPORARY - FOR TESTING ONLY]
// @param balances_addr : deployed address of IBalancesContract [TEMPORARY - FOR TESTING ONLY]
// @param market : market to which bid is being submitted
// @param limit : limit tree to which bid is being submitted
// @param price : limit price of order
// @param amount : order size in number of tokens of quote asset
// @return success : 1 if successfully created bid, 0 otherwise
func create_ask_helper{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    orders_addr : felt, limits_addr : felt, balances_addr : felt, market : Market, limit : Limit, 
    price : felt, amount : felt
) -> (success : felt) {
    alloc_locals;
    let (caller) = get_caller_address();
    let (account_balance) = IBalancesContract.get_balance(balances_addr, caller, market.quote_asset, 1);
    let balance_sufficient = is_le(amount, account_balance);
    %{ print("[markets.cairo] create_ask_helper > balance_sufficient: {}".format(ids.balance_sufficient)) %}
    if (balance_sufficient == 0) {
        handle_revoked_refs();
        return (success=0);
    } else {
        handle_revoked_refs();
    }

    let (dt) = get_block_timestamp();
    let (new_order) = IOrdersContract.push(orders_addr, 0, price, amount, dt, caller, limit.id);
    let (new_head, new_tail) = IOrdersContract.get_head_and_tail(orders_addr, limit.id);
    let (update_limit_success) = ILimitsContract.update(limits_addr, limit.id, limit.total_vol + amount, limit.order_len + 1, new_head, new_tail);
    assert update_limit_success = 1;

    let (lowest_ask) = IOrdersContract.get_order(orders_addr, market.lowest_ask);
    let lowest_ask_exists = is_le(1, lowest_ask.id); 
    let is_not_lowest_ask = is_le(lowest_ask.price, price - 1);
    %{ print("[markets.cairo] create_ask_helper > lowest_ask_exists: {}".format(ids.lowest_ask_exists)) %}
    %{ print("[markets.cairo] create_ask_helper > is_not_lowest_ask: {}".format(ids.is_not_lowest_ask)) %}
    if (lowest_ask_exists + is_not_lowest_ask == 2) {
        handle_revoked_refs();        
    } else {
        let (update_market_success) = update_inside_quote(market.id, new_order.id, market.highest_bid);
        assert update_market_success = 1;
        handle_revoked_refs();
    }
    let (update_balance_success) = IBalancesContract.transfer_to_order(balances_addr, caller, market.quote_asset, amount);
    assert update_balance_success = 1;

    log_create_ask.emit(id=new_order.id, limit_id=limit.id, market_id=market.id, dt=dt, owner=caller, base_asset=market.base_asset, quote_asset=market.quote_asset, price=price, amount=amount);

    return (success=1);
}

// Submit a new market buy order to a given market.
// @param orders_addr : deployed address of IOrdersContract [TEMPORARY - FOR TESTING ONLY]
// @param limits_addr : deployed address of ILimitsContract [TEMPORARY - FOR TESTING ONLY]
// @param balances_addr : deployed address of IBalancesContract [TEMPORARY - FOR TESTING ONLY]
// @param market_id : ID of market
// @param max_price : highest price at which buyer is willing to fulfill order
// @param amount : order size in number of tokens of quote asset
// @return success : 1 if successfully created bid, 0 otherwise
func buy{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    orders_addr : felt, limits_addr : felt, balances_addr : felt, market_id : felt, max_price : felt, 
    amount : felt) -> (success : felt
) {
    alloc_locals;

    let (market) = markets.read(market_id);
    print_market(market);
    let (lowest_ask) = IOrdersContract.get_order(orders_addr, market.lowest_ask);
    let lowest_ask_exists = is_le(1, lowest_ask.id);
    %{ print("[markets.cairo] buy > lowest_ask_exists: {}".format(ids.lowest_ask_exists)) %}
    if (lowest_ask_exists == 0) {
        handle_revoked_refs();
        return (success=0);
    } else {
        handle_revoked_refs();
    }
    let (base_amount, _) = unsigned_div_rem(amount, lowest_ask.price);
    let (caller) = get_caller_address();
    let (account_balance) = IBalancesContract.get_balance(balances_addr, caller, market.base_asset, 1);
    let is_sufficient = is_le(base_amount, account_balance);
    let is_positive = is_le(1, amount);
    %{ print("[markets.cairo] buy > is_sufficient: {}, is_positive: {}, market.id: {}, lowest_ask.id: {}".format(ids.is_sufficient, ids.is_positive, ids.market.id, ids.lowest_ask.id)) %}
    if (is_sufficient * is_positive * market.id * lowest_ask.id == 0) {
        handle_revoked_refs();
        return (success=0);
    } else {
        handle_revoked_refs();
    }

    let is_below_max_price = is_le(lowest_ask.price, max_price);
    let is_partial_fill = is_le(amount, lowest_ask.amount - lowest_ask.filled - 1);
    %{ print("[markets.cairo] buy > is_below_max_price: {}".format(ids.is_below_max_price)) %}
    if (is_below_max_price == 0) {
        create_bid(orders_addr, limits_addr, balances_addr, market_id, max_price, amount);
        handle_revoked_refs();
        return (success=1);
    } else {
        handle_revoked_refs();
    }
    
    let (dt) = get_block_timestamp();
    %{ print("[markets.cairo] buy > is_partial_fill: {}".format(ids.is_partial_fill)) %}
    if (is_partial_fill == 1) {
        // Partial fill of order
        IOrdersContract.set_filled(orders_addr, lowest_ask.id, amount);
        let (success) = IBalancesContract.fill_order(balances_addr, caller, lowest_ask.owner, market.base_asset, market.quote_asset, amount, lowest_ask.price);
        assert success = 1;
        log_offer_taken.emit(id=lowest_ask.id, limit_id=market.ask_tree_id, market_id=market.id, dt=dt, owner=lowest_ask.owner, buyer=caller, base_asset=market.base_asset, quote_asset=market.quote_asset, price=lowest_ask.price, amount=amount, total_filled=lowest_ask.filled + amount);
        handle_revoked_refs();
        return (success=1);
    } else {
        // Fill entire order
        IOrdersContract.set_filled(orders_addr, lowest_ask.id, lowest_ask.amount);
        IOrdersContract.shift(orders_addr, lowest_ask.limit_id);
        let (limit) = ILimitsContract.get_limit(limits_addr, lowest_ask.limit_id);
        let (new_head_id, new_tail_id) = IOrdersContract.get_head_and_tail(orders_addr, limit.id);
        %{ print("[markets.cairo] buy > ILimitsContract.update({}, {}, {}, {}, {})".format(ids.limit.id, ids.limit.total_vol - ids.lowest_ask.amount + ids.lowest_ask.filled, ids.limit.order_len - 1, ids.new_head_id, ids.new_tail_id)) %}
        let (update_limit_success) = ILimitsContract.update(limits_addr, limit.id, limit.total_vol - lowest_ask.amount + lowest_ask.filled, limit.order_len - 1, new_head_id, new_tail_id);                
        assert update_limit_success = 1;

        %{ print("[markets.cairo] buy > new_head_id: {}".format(ids.new_head_id)) %}
        if (new_head_id == 0) {
            ILimitsContract.delete(limits_addr, lowest_ask.price, market.ask_tree_id, market.id);
            let (next_limit) = ILimitsContract.get_min(limits_addr, market.ask_tree_id);
            %{ print("[markets.cairo] buy > next_limit.id: {}".format(ids.next_limit.id)) %}
            if (next_limit.id == 0) {
                let (update_market_success) = update_inside_quote(market.id, 0, market.highest_bid);
                assert update_market_success = 1;
                handle_revoked_refs();
            } else {
                let (next_head, _) = IOrdersContract.get_head_and_tail(orders_addr, next_limit.id);
                let (update_market_success) = update_inside_quote(market.id, next_head, market.highest_bid);
                assert update_market_success = 1;
                handle_revoked_refs();
            }
            handle_revoked_refs();
        } else {
            let (update_market_success) = update_inside_quote(market.id, new_head_id, market.highest_bid);
            assert update_market_success = 1;
            handle_revoked_refs();
        }
        let (update_account_balance_success) = IBalancesContract.fill_order(balances_addr, caller, lowest_ask.owner, market.base_asset, market.quote_asset, lowest_ask.amount, lowest_ask.price);
        assert update_account_balance_success = 1;

        log_offer_taken.emit(id=lowest_ask.id, limit_id=limit.id, market_id=market.id, dt=dt, owner=lowest_ask.owner, buyer=caller, base_asset=market.base_asset, quote_asset=market.quote_asset, price=lowest_ask.price, amount=amount, total_filled=amount);
        log_buy_filled.emit(id=lowest_ask.id, limit_id=limit.id, market_id=market.id, dt=dt, owner=caller, seller=lowest_ask.owner, base_asset=market.base_asset, quote_asset=market.quote_asset, price=lowest_ask.price, amount=amount, total_filled=amount);

        buy(orders_addr, limits_addr, balances_addr, market_id, max_price, amount - lowest_ask.amount); 
        
        handle_revoked_refs();
        return (success=1);
    }
}

func print_market{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (market : Market) {
    %{ 
        print("id: {}, bid_tree_id: {}, ask_tree_id: {}, lowest_ask: {}, highest_bid: {}, base_asset: {}, quote_asset: {}, controller: {}".format(ids.market.id, ids.market.bid_tree_id, ids.market.ask_tree_id, ids.market.lowest_ask, ids.market.highest_bid, ids.market.base_asset, ids.market.quote_asset, ids.market.controller)) 
    %}
    return ();
}

// Utility function to handle revoked implicit references.
// @dev tempvars used to handle revoked implict references
func handle_revoked_refs{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} () {
    tempvar syscall_ptr=syscall_ptr;
    tempvar pedersen_ptr=pedersen_ptr;
    tempvar range_check_ptr=range_check_ptr;
    return ();
}