module suiven::suiven_events {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use suiven::suiven_admin::OrganizerCap;

    // ========== HATALAR ==========
    // E_INVALID_CAPACITY = 100: Kapasite 0'dan büyük olmalı
    // E_INVALID_TIMEFRAME = 101: Başlangıç zamanı bitiş zamanından önce olmalı
    // E_INVALID_ROYALTY = 102: Royalty 0-10000 bps arasında olmalı (0-100%)
    // E_CAPACITY_FULL = 103: Etkinlik kapasitesi doldu

    /// Event: Etkinlik bilgilerini tutan ana yapı
    public struct Event has key, store {
        id: UID,
        organizer: address,
        metadata_uri: vector<u8>, // Walrus CID veya IPFS URI
        start_ts: u64,
        end_ts: u64,
        capacity: u64,
        sold: u64,
        price_amount: u128,
        price_is_sui: bool,
        price_token_type: vector<u8>, // Token type string (opsiyonel)
        royalty_bps: u16, // Basis points (100 = 1%)
        transferable: bool,
        resale_window_end: u64, // Bu zamandan sonra transfer yasak
    }

    /// Yeni bir etkinlik oluşturur
    public fun create_event(
        cap: &OrganizerCap,
        metadata_uri: vector<u8>,
        start_ts: u64,
        end_ts: u64,
        capacity: u64,
        price_amount: u128,
        price_is_sui: bool,
        price_token_type: vector<u8>,
        royalty_bps: u16,
        transferable: bool,
        resale_window_end: u64,
        ctx: &mut TxContext
    ): Event {
        assert!(capacity > 0, 100); // E_INVALID_CAPACITY
        assert!(start_ts < end_ts, 101); // E_INVALID_TIMEFRAME
        assert!(royalty_bps <= 10000, 102); // E_INVALID_ROYALTY

        Event {
            id: object::new(ctx),
            organizer: tx_context::sender(ctx),
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
        }
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
        vector<u8>,
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

    /// Etkinliği shared object olarak paylaşır
    public fun share_event(event: Event) {
        transfer::share_object(event);
    }
}