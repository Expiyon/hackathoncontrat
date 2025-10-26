module suiven::suiven_admin {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    // ========== HATALAR ==========
    // E_NOT_ADMIN = 1: Sadece AdminCap sahibi bu işlemi yapabilir
    // E_INVALID_DECIMALS = 2: Decimals 0-18 arasında olmalı

    /// AdminCap: Paket sahibine verilen yönetici yetkisi
    public struct AdminCap has key, store {
        id: UID,
    }

    /// OrganizerCap: Etkinlik oluşturma yetkisi
    public struct OrganizerCap has key, store {
        id: UID,
        organizer: address,
    }

    /// VerifierCap: Bilet doğrulama ve kullanım işaretleme yetkisi
    public struct VerifierCap has key, store {
        id: UID,
        verifier: address,
    }

    /// TreasuryCap: Token mint/burn yetkisi
    public struct TreasuryCap has key, store {
        id: UID,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
        total_supply: u64,
    }

    /// Paket init fonksiyonu - AdminCap'i publisher'a verir
    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };
        transfer::transfer(admin_cap, tx_context::sender(ctx));
        let organizer_cap = OrganizerCap {
            id: object::new(ctx),
            organizer: ctx.sender(),
        };
        transfer::transfer(organizer_cap, ctx.sender());
    }

    /// Admin tarafından yeni bir organizatör yetkisi verir
    public fun grant_organizer(
        _admin: &AdminCap,
        who: address,
        ctx: &mut TxContext
    ) {
        let organizer_cap = OrganizerCap {
            id: object::new(ctx),
            organizer: who,
        };
        transfer::transfer(organizer_cap, who);
    }

    /// Admin tarafından yeni bir verifier yetkisi verir
    public fun grant_verifier(
        _admin: &AdminCap,
        who: address,
        ctx: &mut TxContext
    ) {
        let verifier_cap = VerifierCap {
            id: object::new(ctx),
            verifier: who,
        };
        transfer::transfer(verifier_cap, who);
    }

    /// Admin tarafından yeni bir fungible token oluşturur
    public fun create_token(
        _admin: &AdminCap,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
        ctx: &mut TxContext
    ): TreasuryCap {
        assert!(decimals <= 18, 2); // E_INVALID_DECIMALS
        TreasuryCap {
            id: object::new(ctx),
            name,
            symbol,
            decimals,
            total_supply: 0,
        }
    }

    /// TreasuryCap bilgilerini döndürür
    public fun get_treasury_info(cap: &TreasuryCap): (vector<u8>, vector<u8>, u8, u64) {
        (cap.name, cap.symbol, cap.decimals, cap.total_supply)
    }

    /// TreasuryCap'in total_supply'ını artırır (mint için)
    public fun increment_supply(cap: &mut TreasuryCap, amount: u64) {
        cap.total_supply = cap.total_supply + amount;
    }

    /// TreasuryCap'in total_supply'ını azaltır (burn için)
    public fun decrement_supply(cap: &mut TreasuryCap, amount: u64) {
        cap.total_supply = cap.total_supply - amount;
    }
}