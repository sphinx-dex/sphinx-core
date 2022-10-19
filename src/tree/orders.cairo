%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import unsigned_div_rem

// Data structure representing an order.
struct Order {
    id : felt,
    next_id : felt,
    prev_id : felt,
    is_buy : felt, // 1 = buy, 0 = sell
    price : felt,
    amount : felt,
    dt : felt,
    owner : felt,
    limit_id : felt,
}

// Stores orders in doubly linked lists.
@storage_var
func orders(id : felt) -> (order : Order) {
}

// Stores heads of doubly linked lists.
@storage_var
func heads(limit_id : felt) -> (id : felt) {
}

// Stores tails of doubly linked lists.
@storage_var
func tails(limit_id : felt) -> (id : felt) {
}

// Stores lengths of doubly linked lists.
@storage_var
func lengths(limit_id : felt) -> (len : felt) {
}

// Stores latest order id.
@storage_var
func curr_order_id() -> (id : felt) {
}

@constructor
func constructor{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} () {
    curr_order_id.write(1);
    return ();
}

// Insert new order to the list.
// @param is_buy : 1 if buy order, 0 if sell order
// @param price : limit price
// @param amount : amount of order
// @param dt : datetime of order entry
// @param owner : owner of order
// @param limit_id : ID of limit price corresponding to order
func push{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (is_buy : felt, price : felt, amount : felt, dt : felt, owner : felt, limit_id : felt) {
    alloc_locals;

    let (id) = curr_order_id.read();
    tempvar new_order: Order* = new Order(
        id=id, next_id=0, prev_id=0, is_buy=is_buy, price=price, amount=amount, dt=dt, owner=owner, limit_id=limit_id
    );
    orders.write(id, [new_order]);
    curr_order_id.write(id + 1);

    let (length) = lengths.read(limit_id);
    if (length == 0) {
        heads.write(limit_id, new_order.id);
        tails.write(limit_id, new_order.id);
        handle_revoked_refs();
    } else {
        let (tail_id) = tails.read(limit_id);
        let (tail) = orders.read(tail_id);
        tempvar new_tail: Order* = new Order(
            id=tail.id, next_id=new_order.id, prev_id=tail.prev_id, is_buy=tail.is_buy, 
            price=tail.price, amount=tail.amount, dt=tail.dt, owner=tail.owner, limit_id=tail.limit_id
        );
        orders.write(tail_id, [new_tail]);
        tempvar new_order_updated: Order* = new Order(
            id=new_order.id, next_id=0, prev_id=tail_id, is_buy=new_order.is_buy, 
            price=new_order.price, amount=new_order.amount, dt=new_order.dt, owner=new_order.owner, 
            limit_id=new_order.limit_id
        );
        orders.write(new_order.id, [new_order_updated]);
        tails.write(limit_id, new_order.id);
        handle_revoked_refs();
    }

    lengths.write(limit_id, length + 1);

    // Diagnostics
    let (head_id) = heads.read(limit_id);
    print_list(head_id, length + 1, 1);

    return ();
}

// Remove order from the end of the list.
// @param limit_id : limit ID of order list being amended
// @return del : order deleted from list (or empty order if list is empty)
func pop{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (limit_id : felt) -> (del : Order) {
    alloc_locals;
    
    let (length) = lengths.read(limit_id);
    tempvar empty_order: Order* = new Order(
        id=0, next_id=0, prev_id=0, is_buy=0, price=0, amount=0, dt=0, owner=0, limit_id=0
    );
    if (length == 0) {
        return (del=[empty_order]);
    }

    let (head_id) = heads.read(limit_id);
    let (old_tail_id) = tails.read(limit_id);
    let (old_tail) = orders.read(old_tail_id);

    if (length - 1 == 0) {
        orders.write(head_id, [empty_order]);
        orders.write(old_tail_id, [empty_order]);
        heads.write(limit_id, 0);
        tails.write(limit_id, 0);
        handle_revoked_refs();
    } else {
        tails.write(limit_id, old_tail.prev_id);
        let (new_tail) = orders.read(old_tail.prev_id);
        tempvar new_tail_updated: Order* = new Order(
            id=new_tail.id, next_id=0, prev_id=new_tail.prev_id, is_buy=new_tail.is_buy, 
            price=new_tail.price, amount=new_tail.amount, dt=new_tail.dt, owner=new_tail.owner, 
            limit_id=new_tail.limit_id
        );
        orders.write(new_tail.id, [new_tail_updated]);
        handle_revoked_refs();
    }

    lengths.write(limit_id, length - 1);

    // Diagnostics
    %{ print("Deleted: ") %}
    print_order(old_tail);
    print_list(head_id, length - 1, 1);

    return (del=old_tail);
}

// Remove order from head of list
// @param limit_id : limit ID of order list being amended
// @return del : deleted order
func shift{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (limit_id : felt) -> (del : Order) {
    alloc_locals;

    let (length) = lengths.read(limit_id);
    tempvar empty_order: Order* = new Order(
        id=0, next_id=0, prev_id=0, is_buy=0, price=0, amount=0, dt=0, owner=0, limit_id=0
    );
    if (length == 0) {
        return (del=[empty_order]);
    }

    let (old_head_id) = heads.read(limit_id);
    let (old_head) = orders.read(old_head_id);

    if (length - 1 == 0) {
        heads.write(limit_id, 0);
        tails.write(limit_id, 0);
        handle_revoked_refs();
    } else {
        heads.write(limit_id, old_head.next_id);
        let (new_head) = orders.read(old_head.next_id);
        tempvar new_head_updated: Order* = new Order(
            id=new_head.id, next_id=new_head.next_id, prev_id=0, is_buy=new_head.is_buy, 
            price=new_head.price, amount=new_head.amount, dt=new_head.dt, owner=new_head.owner, 
            limit_id=new_head.limit_id
        );
        orders.write(new_head.id, [new_head_updated]);
        handle_revoked_refs();
    }

    lengths.write(limit_id, length - 1);

    // Diagnostics
    %{ print("Deleted: ") %}
    print_order(old_head);
    let (head_id) = heads.read(limit_id);
    let length_positive = is_le(1, length - 1);
    if (length_positive == 1) {
        print_list(head_id, length - 1, 1);
        handle_revoked_refs();
    } else {
        %{ 
            print("No orders remaining") 
            print("") 
        %}
        handle_revoked_refs();
    }

    return (del=old_head);
} 

// Retrieve order at particular position in the list.
// @param limit_id : limit ID of order list being amended
// @param idx : order to retrieve
// @return order : retrieved order
func get{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (limit_id : felt, idx : felt) -> (order : Order) {
    alloc_locals;
    
    tempvar empty_order: Order* = new Order(
        id=0, next_id=0, prev_id=0, is_buy=0, price=0, amount=0, dt=0, owner=0, limit_id=0
    );
    let (in_range) = validate_idx(limit_id, idx);
    if (in_range == 0) {
        return (order=[empty_order]);
    }

    let (head_id) = heads.read(limit_id);
    let (head) = orders.read(head_id);
    let (tail_id) = tails.read(limit_id);
    let (tail) = orders.read(tail_id);

    let (length) = lengths.read(limit_id);
    let (half_length, _) = unsigned_div_rem(length, 2);
    let less_than_half = is_le(idx, half_length);

    if (less_than_half == 1) {
        let (order) = locate_item_from_head(i=0, idx=idx, curr=head);
        // Diagnostics
        %{ print("Retrieved: ") %}
        print_order(order);
        return (order=order);
    } else {
        let (order) = locate_item_from_tail(i=length-1, idx=idx, curr=tail);
        // Diagnostics
        %{ print("Retrieved: ") %}
        print_order(order);
        return (order=order);
    }
}

// Iterate through list to find item from head element.
// @param i : current iteration
// @param idx : list position to be found
// @param curr : order in current iteration of the list
func locate_item_from_head{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (i : felt, idx : felt, curr : Order) -> (order : Order) {
    if (i == idx) {
        return (order=curr);
    }
    let (next) = orders.read(curr.next_id);
    return locate_item_from_head(i + 1, idx, next);
}

// Iterate through list to find item from tail element.
// @param i : current iteration
// @param idx : list position to be found
// @param curr : order in current iteration of the list
func locate_item_from_tail{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (i : felt, idx : felt, curr : Order) -> (order : Order) {
    if (i == idx) {
        return (order=curr);
    }
    let (prev) = orders.read(curr.prev_id);
    return locate_item_from_tail(i - 1, idx, prev);
}

// Update order at particular position in the list.
// @param limit_id : limit ID of order list being amended
// @param idx : position of list to insert new value
// @param is_buy : 1 if buy order, 0 if sell order
// @param price : limit price
// @param amount : amount of order
// @param dt : datetime of order entry
// @param owner : owner of order
// @return success : 1 if insertion was successful, 0 otherwise
func set{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (
    limit_id : felt, idx : felt, is_buy : felt, price : felt, amount : felt, dt : felt, owner : felt
) -> (success : felt) {
    let (in_range) = validate_idx(limit_id, idx);
    if (in_range == 0) {
        return (success=0);
    }
    let (order) = get(limit_id, idx);
    tempvar new_order : Order* = new Order(
        id=order.id, next_id=order.next_id, prev_id=order.prev_id, is_buy=is_buy, 
        price=price, amount=amount, dt=dt, owner=owner, limit_id=limit_id
    );
    orders.write(order.id, [new_order]);

    // Diagnostics
    let (head_id) = heads.read(limit_id);
    let (length) = lengths.read(limit_id);
    print_list(head_id, length, 1);

    return (success=1);
}

// Remove value at particular position in the list.
// @param limit_id : limit ID of order list being amended
// @param idx : list item to be deleted
// @return del : deleted Order
func remove{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (limit_id : felt, idx : felt) -> (del : Order) {
    alloc_locals;

    tempvar empty_order: Order* = new Order(
        id=0, next_id=0, prev_id=0, is_buy=0, price=0, amount=0, dt=0, owner=0, limit_id=0
    );
    let (in_range) = validate_idx(limit_id, idx);
    if (in_range == 0) {
        return (del=[empty_order]);
    }
    let (length) = lengths.read(limit_id);
    if (idx == length - 1) {
        let (del) = pop(limit_id);
        return (del=del);
    }
    if (idx == 0) {
        let (del) = shift(limit_id);
        return (del=del);
    }

    let (removed_order) = get(limit_id, idx);
    let (removed) = orders.read(removed_order.id);

    let (removed_prev) = orders.read(removed.prev_id);
    tempvar updated_removed_prev: Order* = new Order(
        id=removed_prev.id, next_id=removed.next_id, prev_id=removed_prev.prev_id, is_buy=removed_prev.is_buy, 
        price=removed_prev.price, amount=removed_prev.amount, dt=removed_prev.dt, owner=removed_prev.owner, 
        limit_id=removed_prev.limit_id
    ); 
    orders.write(removed_prev.id, [updated_removed_prev]);

    let (removed_next) = orders.read(removed.next_id);
    tempvar updated_removed_next: Order* = new Order(
        id=removed_next.id, next_id=removed_next.next_id, prev_id=removed.prev_id, is_buy=removed_next.is_buy, 
        price=removed_next.price, amount=removed_next.amount, dt=removed_next.dt, owner=removed_next.owner, 
        limit_id=removed_next.limit_id
    ); 
    orders.write(removed_next.id, [updated_removed_next]);

    lengths.write(limit_id, length - 1);

    // Diagnostics
    let (head_id) = heads.read(limit_id);
    print_list(head_id, length + 1, 1);

    return (del=removed);
}

// Utility function to check idx is not out of bounds.
// @param idx : index to check
// @return in_range : 1 if idx in range, 0 otherwise
func validate_idx{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (limit_id : felt, idx : felt) -> (in_range : felt) {
    alloc_locals;
    
    let (length) = lengths.read(limit_id);
    let idx_negative = is_le(idx, -1);
    let idx_out_of_bounds = is_le(length, idx);

    if ((idx_negative - 1) * (idx_out_of_bounds - 1) == 0) {
        handle_revoked_refs();
        return (in_range=0);
    } else {
        handle_revoked_refs();
        return (in_range=1);
    }
}

// Utility function for printing list.
func print_list{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (node_loc : felt, idx: felt, first_iter : felt) {
    if (first_iter == 1) {
        %{
            print("Orders:")
        %}
        tempvar temp;
    }
    if (idx == 0) {
        %{
            print("")
        %}
        return ();
    }
    let (order) = orders.read(node_loc);
    %{
        print("    ", end="")
        print("id: {}, next_id: {}, prev_id: {}, is_buy: {}, price: {}, amount: {}, dt: {}, owner: {}, limit_id: {}".format(ids.order.id, ids.order.next_id, ids.order.prev_id, ids.order.is_buy, ids.order.price, ids.order.amount, ids.order.dt, ids.order.owner, ids.order.limit_id))
    %}
    return print_list(order.next_id, idx - 1, 0);
}

// Utility function for printing order.
func print_order{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} (order : Order) {
    %{
        print("    ", end="")
        print("id: {}, next_id: {}, prev_id: {}, is_buy: {}, price: {}, amount: {}, dt: {}, owner: {}, limit_id: {}".format(ids.order.id, ids.order.next_id, ids.order.prev_id, ids.order.is_buy, ids.order.price, ids.order.amount, ids.order.dt, ids.order.owner, ids.order.limit_id))
    %}
    return ();
}

// Utility function to handle revoked implicit references.
// @dev tempvars used to handle revoked implict references
func handle_revoked_refs{
    syscall_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
} () {
    tempvar syscall_ptr=syscall_ptr;
    tempvar pedersen_ptr=pedersen_ptr;
    tempvar range_check_ptr=range_check_ptr;
    return ();
}