module suiven::suiven_token {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use suiven::suiven_admin::TreasuryCap;

    // ========== HATALAR ==========
    // E_INSUFFICIENT_BALANCE = 400: Yetersiz bakiye
    // E_INVALID_AMOUNT = 401: Miktar 0'dan büyük olmalı

    /// TokenBalance: Kullanıcının token bakiyesi
    public struct TokenBalance has key, store {
        id: UID,
        token_name: vector<u8>,
        amount: u64,
        owner: address,
    }

    /// Yeni token mint eder ve kullanıcıya gönderir
    public fun mint(
        cap: &mut TreasuryCap,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        assert!(amount > 0, 401); // E_INVALID_AMOUNT

        let (name, _, _, _) = suiven::suiven_admin::get_treasury_info(cap);
        suiven::suiven_admin::increment_supply(cap, amount);

        let balance = TokenBalance {
            id: object::new(ctx),
            token_name: name,
            amount,
            owner: recipient,
        };

        transfer::transfer(balance, recipient);
    }

    /// Token yakarak imha eder
    public fun burn(
        cap: &mut TreasuryCap,
        balance: TokenBalance,
        _ctx: &mut TxContext
    ) {
        let TokenBalance { id, token_name: _, amount, owner: _ } = balance;
        object::delete(id);
        
        suiven::suiven_admin::decrement_supply(cap, amount);
    }

    /// Token bakiyesini döndürür
    public fun get_balance(balance: &TokenBalance): u64 {
        balance.amount
    }

    /// Token bakiye sahibini döndürür
    public fun get_balance_owner(balance: &TokenBalance): address {
        balance.owner
    }

    /// İki bakiyeyi birleştirir
    public fun merge(
        balance1: &mut TokenBalance,
        balance2: TokenBalance,
        _ctx: &mut TxContext
    ) {
        let TokenBalance { id, token_name: _, amount, owner: _ } = balance2;
        balance1.amount = balance1.amount + amount;
        object::delete(id);
    }

    /// Bakiyeyi böler
    public fun split(
        balance: &mut TokenBalance,
        amount: u64,
        ctx: &mut TxContext
    ): TokenBalance {
        assert!(balance.amount >= amount, 400); // E_INSUFFICIENT_BALANCE
        assert!(amount > 0, 401); // E_INVALID_AMOUNT

        balance.amount = balance.amount - amount;

        TokenBalance {
            id: object::new(ctx),
            token_name: balance.token_name,
            amount,
            owner: balance.owner,
        }
    }

    /// Token bakiyesini transfer eder
    public fun transfer_balance(balance: TokenBalance, to: address) {
        transfer::transfer(balance, to);
    }
}