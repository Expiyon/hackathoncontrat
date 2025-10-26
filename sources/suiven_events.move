module suiven::suiven_events {
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use suiven::suiven_admin::{OrganizerCap, AdminCap};

    // ========== EVENTS ==========
    public struct EventCreated has copy, drop {
        event_id: ID,
        organizer: address,
        metadata_uri: std::string::String,
        start_ts: u64,
        end_ts: u64,
        capacity: u64,
        price_amount: u128,
        price_is_sui: bool,
        royalty_bps: u16,
        transferable: bool,
    }

    // ========== HATALAR ==========
    // E_INVALID_CAPACITY = 100: Kapasite 0'dan büyük olmalı
    // E_INVALID_TIMEFRAME = 101: Başlangıç zamanı bitiş zamanından önce olmalı
    // E_INVALID_ROYALTY = 102: Royalty 0-10000 bps arasında olmalı (0-100%)
    // E_CAPACITY_FULL = 103: Etkinlik kapasitesi doldu

    /// Event: Etkinlik bilgilerini tutan ana yapı
    public struct Event has key, store {
        id: UID,
        organizer: address,
        event_name: std::string::String, // Etkinlik adı
        metadata_uri: std::string::String, // Walrus CID veya IPFS URI
        start_ts: u64,
        end_ts: u64,
        capacity: u64,
        sold: u64,
        price_amount: u128,
        price_is_sui: bool,
        price_token_type: std::string::String, // Token type string (opsiyonel)
        royalty_bps: u16, // Basis points (100 = 1%)
        transferable: bool,
        resale_window_end: u64, // Bu zamandan sonra transfer yasak
        balance: Balance<SUI>, // Toplanan fonlar
    }

    /// Yeni bir etkinlik oluşturur
    public fun create_event(
        _cap: &OrganizerCap,
        event_name: std::string::String,
        metadata_uri: std::string::String,
        start_ts: u64,
        end_ts: u64,
        capacity: u64,
        price_amount: u128,
        price_is_sui: bool,
        price_token_type: std::string::String,
        royalty_bps: u16,
        transferable: bool,
        resale_window_end: u64,
        ctx: &mut TxContext
    ) {
        assert!(capacity > 0, 100); // E_INVALID_CAPACITY
        assert!(start_ts < end_ts, 101); // E_INVALID_TIMEFRAME
        assert!(royalty_bps <= 10000, 102); // E_INVALID_ROYALTY

        let event_uid = object::new(ctx);
        let event_id = object::uid_to_inner(&event_uid);

        let event = Event {
            id: event_uid,
            organizer: tx_context::sender(ctx),
            event_name,
            metadata_uri,
            start_ts,
            end_ts,
            capacity,
            sold: 0,
            price_amount,
            price_is_sui,
            price_token_type,
            royalty_bps,
            transferable,
            resale_window_end,
            balance: balance::zero<SUI>(),
        };

        // Emit event creation
        event::emit(EventCreated {
            event_id,
            organizer: tx_context::sender(ctx),
            metadata_uri,
            start_ts,
            end_ts,
            capacity,
            price_amount,
            price_is_sui,
            royalty_bps,
            transferable,
        });

        // Etkinliği shared object olarak paylaşır
        transfer::share_object(event);
    }

    /// Etkinliğin satılan bilet sayısını artırır (sadece ticket modülü tarafından çağrılır)
    public(package) fun increment_sold(event: &mut Event) {
        assert!(event.sold < event.capacity, 103); // E_CAPACITY_FULL
        event.sold = event.sold + 1;
    }

    /// Etkinlik bilgilerini döndürür
    public fun get_event_info(event: &Event): (
        ID,
        address,
        std::string::String,
        std::string::String,
        u64,
        u64,
        u64,
        u64,
        u128,
        bool,
        u16,
        bool,
        u64
    ) {
        (
            object::uid_to_inner(&event.id),
            event.organizer,
            event.event_name,
            event.metadata_uri,
            event.start_ts,
            event.end_ts,
            event.capacity,
            event.sold,
            event.price_amount,
            event.price_is_sui,
            event.royalty_bps,
            event.transferable,
            event.resale_window_end
        )
    }

    /// Etkinlik doluluk oranını döndürür
    public fun is_sold_out(event: &Event): bool {
        event.sold >= event.capacity
    }

    /// Etkinliğin organizatör adresini döndürür
    public fun get_organizer(event: &Event): address {
        event.organizer
    }

    /// Etkinliğin royalty bilgisini döndürür
    public fun get_royalty_bps(event: &Event): u16 {
        event.royalty_bps
    }

    /// Etkinliğin transfer kurallarını döndürür
    public fun get_transfer_rules(event: &Event): (bool, u64) {
        (event.transferable, event.resale_window_end)
    }

    /// Etkinlik adını döndürür
    public fun get_event_name(event: &Event): std::string::String {
        event.event_name
    }

    /// Ödemeyi etkinlik bakiyesine ekler (sadece ticket modülü tarafından çağrılır)
    public(package) fun deposit_payment(event: &mut Event, payment: Balance<SUI>) {
        balance::join(&mut event.balance, payment);
    }

    /// Etkinlik bakiyesinin değerini döndürür
    public fun get_balance_value(event: &Event): u64 {
        balance::value(&event.balance)
    }

    /// Admin tarafından toplanan fonları çeker
    public fun withdraw_funds(
        _admin: &AdminCap,
        event: &mut Event,
        ctx: &mut TxContext
    ) {
        let amount = balance::value(&event.balance);
        if (amount > 0) {
            let withdrawn = balance::withdraw_all(&mut event.balance);
            let coin = coin::from_balance(withdrawn, ctx);
            transfer::public_transfer(coin, tx_context::sender(ctx));
        }
    }

    /// Entry point: Admin toplanan fonları çeker
    public entry fun admin_withdraw_event_funds(
        admin: &AdminCap,
        event: &mut Event,
        ctx: &mut TxContext
    ) {
        withdraw_funds(admin, event, ctx);
    }
}