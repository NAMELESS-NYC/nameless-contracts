module my_management_addr::nameless_management_v1 {
    use std::signer;
    use std::error;
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account;
    use aptos_framework::aptos_account;
    use aptos_framework::event;
    use aptos_framework::timestamp;

    #[test_only]
    use aptos_std::debug::print;

    const ENO_ACCESS: u64 = 100;
    const ENOT_OWNER: u64 = 101;
    const ENO_RECEIVER_ACCOUNT: u64 = 102;
    const ENOT_ADMIN: u64 = 103;
    const ENOT_VALID_TOKEN: u64 = 104;
    const ENOT_TOKEN_OWNER: u64 = 105;
    const EINVALID_DATE_OVERRIDE: u64 = 106;

    #[test_only]
    const EINVALID_UPDATE: u64 = 107;

    const EMPTY_STRING: vector<u8> = b"";
    const ORGANIZATIONS_COLLECTION_NAME: vector<u8> = b"NAMELESS_MANAGEMENT_ORGANIZATIONS";

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct NamelessConfig has key {
        admin: address,
        base_uri: String,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct NamelessOrganization has key {
        id: String,
        name: String,
        admin: address,
        transfer_events: event::EventHandle<NamelessOrganizationCreationEvent>,
        transfer_ref: object::TransferRef,
        mutator_ref: token::MutatorRef,
        extend_ref: object::ExtendRef
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct NamelessCollection has key {
        id: String,
        name: String,
        start_date: u64,
        end_date: u64,
        supply: u64,
        organization: Object<NamelessOrganization>,
        transfer_events: event::EventHandle<NamelessCollectionCreationEvent>,
        transfer_ref: object::TransferRef,
        mutator_ref: collection::MutatorRef,
        extend_ref: object::ExtendRef
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct NamelessReward has key {
        id: String,
        reward_type_id: String,
        collection: Object<NamelessCollection>,
        organization: Object<NamelessOrganization>,
        redeemed_by: Option<address>,
        redeemed_at: u64,
        reward_uri: String,
        transfer_events: event::EventHandle<NamelessRewardTransferEvent>,
        redeem_events: event::EventHandle<NamelessRewardRedeemEvent>,
        transfer_ref: object::TransferRef,
        mutator_ref: token::MutatorRef,
        extend_ref: object::ExtendRef
    }

    struct NamelessRewardTransferEvent has drop, store {
        reward_address: address,
        receiver_address: address,
        collection_address: address,
        creation_timestamp: u64,
        reward_uri: String
    }

    struct NamelessRewardRedeemEvent has drop, store {
        reward_address: address,
        redeemer_address: address,
        collection_address: address,
        redemption_timestamp: u64,
    }

    struct NamelessOrganizationCreationEvent has drop, store {
        organization_address: address,
        organization_id: String,
        organization_name: String,
        creation_timestamp: u64,
    }

    struct NamelessCollectionCreationEvent has drop, store {
        collection_address: address,
        collection_id: String,
        collection_name: String,
        creation_timestamp: u64,
        organization_address: address,
        start_date: u64,
        end_date: u64,
        supply: u64,
    }

    fun init_module(sender: &signer) {
        let base_uri = string::utf8(b"https://aptos-metadata.s3.us-east-2.amazonaws.com/baseUri/");

        let on_chain_config = NamelessConfig {
            admin: signer::address_of(sender),
            base_uri
        };
        move_to(sender, on_chain_config);

        let description = string::utf8(EMPTY_STRING);
        let name = string::utf8(ORGANIZATIONS_COLLECTION_NAME);
        let uri = generate_org_uri_from_id(base_uri,string::utf8(ORGANIZATIONS_COLLECTION_NAME));

        collection::create_unlimited_collection(
            sender,
            description,
            name,
            option::none(),
            uri,
        );
    }

    entry public fun create_organization(admin: &signer, organization_id: String, organization_name: String) acquires NamelessConfig, NamelessOrganization {
        let nameless_config_obj = is_admin(admin);

        let uri = generate_org_uri_from_id(nameless_config_obj.base_uri, organization_id);

        let token_constructor_ref = token::create_named_token(admin, string::utf8(ORGANIZATIONS_COLLECTION_NAME), string::utf8(EMPTY_STRING), organization_id, option::none(), uri);
        let object_signer = object::generate_signer(&token_constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&token_constructor_ref);
        let mutator_ref = token::generate_mutator_ref(&token_constructor_ref);
        let extend_ref = object::generate_extend_ref(&token_constructor_ref);

        object::disable_ungated_transfer(&transfer_ref);

        let organization = NamelessOrganization {
            id: organization_id,
            name: organization_name,
            admin: nameless_config_obj.admin,
            transfer_events: object::new_event_handle(&object_signer),
            transfer_ref: transfer_ref,
            mutator_ref: mutator_ref,
            extend_ref: extend_ref
        };


        move_to(&object_signer, organization);
        let organization_obj = borrow_global_mut<NamelessOrganization>(object::address_from_constructor_ref(&token_constructor_ref));

        event::emit_event<NamelessOrganizationCreationEvent>(
            &mut organization_obj.transfer_events,
            NamelessOrganizationCreationEvent {
                organization_address: generate_organization_address(signer::address_of(admin), organization_obj.id),
                organization_id: organization_obj.id,
                organization_name: organization_obj.name,
                creation_timestamp: timestamp::now_seconds(),
            }
        );
    }

    entry public fun create_collection(admin: &signer, organization: Object<NamelessOrganization>, collection_id: String, collection_name: String, supply: u64, start_date: u64, end_date: u64 ) acquires NamelessConfig, NamelessOrganization, NamelessCollection {
        let nameless_config_obj = is_admin(admin);

        let org_obj = borrow_global_mut<NamelessOrganization>(object::object_address(&organization));

        let uri = generate_collection_uri_from_id(nameless_config_obj.base_uri, org_obj.id, collection_id);

        let collection_constructor_ref = collection::create_fixed_collection(
            admin,
            string::utf8(EMPTY_STRING),
            supply,
            collection_id,
            option::none(),
            uri,
        );
        let object_signer = object::generate_signer(&collection_constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&collection_constructor_ref);
        let mutator_ref = collection::generate_mutator_ref(&collection_constructor_ref);
        let extend_ref = object::generate_extend_ref(&collection_constructor_ref);

        object::disable_ungated_transfer(&transfer_ref);

        let collection = NamelessCollection {
            id: collection_id,
            name: collection_name,
            start_date,
            end_date,
            supply,
            organization,
            transfer_events: object::new_event_handle(&object_signer),
            transfer_ref,
            mutator_ref,
            extend_ref
        };

        move_to(&object_signer, collection);
        let collection_obj = borrow_global_mut<NamelessCollection>(object::address_from_constructor_ref(&collection_constructor_ref));
        event::emit_event<NamelessCollectionCreationEvent>(
            &mut collection_obj.transfer_events,
            NamelessCollectionCreationEvent {
                collection_address: generate_collection_address(signer::address_of(admin), collection_obj.id),
                collection_id: collection_obj.id,
                collection_name: collection_obj.name,
                creation_timestamp: timestamp::now_seconds(),
                organization_address: object::object_address(&organization),
                start_date: collection_obj.start_date,
                end_date: collection_obj.end_date,
                supply: collection_obj.supply
            }
        );
    }

entry public fun create_reward(admin: &signer, receiver: address, collection: Object<NamelessCollection>, reward_type_id: String, reward_id: String)
    acquires NamelessConfig, NamelessCollection, NamelessReward, NamelessOrganization {  
        let nameless_config_obj = is_admin(admin);
        let sender_addr = signer::address_of(admin);

        if(!account::exists_at(receiver)) {
            aptos_account::create_account(receiver);
        };
        
        let collection_obj = borrow_global_mut<NamelessCollection>(object::object_address(&collection));
        let org_obj = borrow_global_mut<NamelessOrganization>(object::object_address(&collection_obj.organization));

        let uri = generate_reward_uri_from_id(nameless_config_obj.base_uri, org_obj.id, collection_obj.id, reward_type_id);

        let time_now = timestamp::now_seconds();

        if (time_now >= collection_obj.start_date && time_now <= collection_obj.end_date) {
            let token_constructor_ref = token::create_named_token(admin, collection_obj.id, string::utf8(EMPTY_STRING), reward_id, option::none(), uri);
            let object_signer = object::generate_signer(&token_constructor_ref);
            let transfer_ref = object::generate_transfer_ref(&token_constructor_ref);
            let mutator_ref = token::generate_mutator_ref(&token_constructor_ref);
            let extend_ref = object::generate_extend_ref(&token_constructor_ref);

            object::disable_ungated_transfer(&transfer_ref);

            let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);
            object::transfer_with_ref(linear_transfer_ref, receiver);

            let reward = NamelessReward {
                id: reward_id,
                collection,
                reward_type_id,
                organization: collection_obj.organization,
                redeemed_at: 0,
                redeemed_by: option::none(),
                reward_uri: uri,
                transfer_events: object::new_event_handle(&object_signer),
                redeem_events: object::new_event_handle(&object_signer),
                transfer_ref,
                mutator_ref,
                extend_ref
            };

            move_to(&object_signer, reward);

            let reward_obj = borrow_global_mut<NamelessReward>(object::address_from_constructor_ref(&token_constructor_ref));
            event::emit_event<NamelessRewardTransferEvent>(
                &mut reward_obj.transfer_events,
                NamelessRewardTransferEvent {
                    reward_address: generate_reward_address(sender_addr, collection_obj.id, reward_id),
                    collection_address: object::object_address(&collection),
                    receiver_address: receiver,
                    creation_timestamp: time_now,
                    reward_uri: uri  
                }
            );
        }
    }

    entry public fun transfer_reward(admin: &signer, receiver: address, reward: Object<NamelessReward>) acquires NamelessConfig, NamelessReward {
        is_admin(admin);

        if(!account::exists_at(receiver)) {
            aptos_account::create_account(receiver);
        };

        let reward_obj = borrow_global_mut<NamelessReward>(object::object_address(&reward));
        
        let linear_transfer_ref = object::generate_linear_transfer_ref(&reward_obj.transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, receiver);

        event::emit_event<NamelessRewardTransferEvent>(
            &mut reward_obj.transfer_events,
            NamelessRewardTransferEvent {
                reward_address: object::object_address(&reward),
                receiver_address: receiver,
                collection_address: object::object_address(&reward_obj.collection),
                creation_timestamp: timestamp::now_seconds(),
                reward_uri: reward_obj.reward_uri
            }
        );
    }

    entry public fun redeem_reward(admin: &signer, reward: Object<NamelessReward>) acquires NamelessConfig, NamelessReward {
        is_admin(admin);

        let reward_obj = borrow_global_mut<NamelessReward>(object::object_address(&reward));

        let owner_addr = object::owner(reward);
        let redeemed_by = &mut reward_obj.redeemed_by;
        option::fill(redeemed_by, owner_addr);
        reward_obj.redeemed_at = timestamp::now_seconds();

        event::emit_event<NamelessRewardRedeemEvent>(
            &mut reward_obj.redeem_events,
            NamelessRewardRedeemEvent {
                reward_address: object::object_address(&reward),
                redeemer_address: owner_addr,
                collection_address: object::object_address(&reward_obj.collection),
                redemption_timestamp: timestamp::now_seconds()
            }
        );
    }

    // entry public fun update_organization_uri(admin: &signer, organization: Object<NamelessOrganization>) acquires NamelessConfig, NamelessOrganization {
    //     let nameless_config_obj = is_admin(admin);

    //     let organization_obj = borrow_global_mut<NamelessOrganization>(object::object_address(&organization));
    //     let uri = generate_org_uri_from_id(nameless_config_obj.base_uri, organization_obj.id);

    //     token::set_uri(&organization_obj.mutator_ref, uri);
    // }

    // entry public fun update_collection_uri(admin: &signer, nameless_collection: Object<NamelessCollection>) acquires NamelessConfig, NamelessCollection, NamelessOrganization {
    //     let nameless_config_obj = is_admin(admin);

    //     let collection_obj = borrow_global_mut<NamelessCollection>(object::object_address(&nameless_collection));
    //     let org_obj = borrow_global<NamelessOrganization>(object::object_address(&collection_obj.organization));

    //     let uri = generate_collection_uri_from_id(nameless_config_obj.base_uri, org_obj.id, collection_obj.id);

    //     collection::set_uri(&collection_obj.mutator_ref, uri);
    // }

    // entry public fun update_token_uri(admin: &signer, nameless_collection: Object<NamelessCollection>, nameless_token: Object<NamelessToken>) acquires NamelessConfig, NamelessToken, NamelessCollection, NamelessOrganization {
    //     let nameless_config_obj = is_admin(admin);
    //     let collection_obj = borrow_global_mut<NamelessCollection>(object::object_address(&nameless_collection));
    //     let org_obj = borrow_global<NamelessOrganization>(object::object_address(&collection_obj.organization));
    //     let token_obj = borrow_global_mut<NamelessToken>(object::object_address(&nameless_token));
    //     let uri = generate_token_uri_from_id(nameless_config_obj.base_uri, org_obj.id, collection_obj.id, token_obj.token_type_id);

    //     token::set_uri(&token_obj.mutator_ref, uri);
    // }

    entry public fun update_collection_name(admin: &signer, nameless_collection: Object<NamelessCollection>, name: String) acquires NamelessConfig, NamelessCollection {
        is_admin(admin);

        let collection_obj = borrow_global_mut<NamelessCollection>(object::object_address(&nameless_collection));
        collection_obj.name = name;
    }

    entry public fun update_collection_start_date(admin: &signer, nameless_collection: Object<NamelessCollection>, start_date: u64) acquires NamelessConfig, NamelessCollection {
        is_admin(admin);

        let collection_obj = borrow_global_mut<NamelessCollection>(object::object_address(&nameless_collection));
        collection_obj.start_date = start_date;
    }

    entry public fun update_collection_end_date(admin: &signer, nameless_collection: Object<NamelessCollection>, end_date: u64) acquires NamelessConfig, NamelessCollection {
        is_admin(admin);

        let collection_obj = borrow_global_mut<NamelessCollection>(object::object_address(&nameless_collection));
        collection_obj.end_date = end_date;
    }

    entry public fun update_organization_name(admin: &signer, organization: Object<NamelessOrganization>, name: String) acquires NamelessConfig, NamelessOrganization {
        is_admin(admin);

        let organization_obj = borrow_global_mut<NamelessOrganization>(object::object_address(&organization));
        organization_obj.name = name;
    }

    inline fun is_admin(admin: &signer): &NamelessConfig {
        let admin_addr = signer::address_of(admin);
        let nameless_config_obj = borrow_global<NamelessConfig>(admin_addr);
        assert!(nameless_config_obj.admin == admin_addr, error::permission_denied(ENOT_ADMIN));

        nameless_config_obj
    }

    public fun validate_reward(collection: Object<NamelessCollection>, reward: Object<NamelessReward>) acquires NamelessReward, NamelessCollection {
        let reward_obj = borrow_global<NamelessReward>(object::object_address(&reward));
        let reward_collection_obj = borrow_global<NamelessCollection>(object::object_address(&reward_obj.collection));
        let collection_obj = borrow_global<NamelessCollection>(object::object_address(&collection));

        assert!(
            collection_obj.id == reward_collection_obj.id,
            error::permission_denied(ENOT_VALID_TOKEN),
        );
    }

    fun generate_org_uri_from_id(base_uri: String, id: String): String {
        let base_uri_bytes = string::bytes(&base_uri);
        let uri = string::utf8(*base_uri_bytes);
        string::append(&mut uri, id);
        string::append_utf8(&mut uri, b"/metadata.json");

        uri
    }

      fun generate_collection_uri_from_id(base_uri: String, org_id: String, collection_id: String): String {
        let base_uri_bytes = string::bytes(&base_uri);
        let uri = string::utf8(*base_uri_bytes);
        string::append(&mut uri, org_id);
        string::append_utf8(&mut uri, b"/");
        string::append(&mut uri, collection_id);
        string::append_utf8(&mut uri, b"/metadata.json");

        uri
    }

      fun generate_reward_uri_from_id(base_uri: String, org_id: String, collection_id: String, reward_type_id: String): String {
        let base_uri_bytes = string::bytes(&base_uri);
        let uri = string::utf8(*base_uri_bytes);
        string::append(&mut uri, org_id);
        string::append_utf8(&mut uri, b"/");
        string::append(&mut uri, collection_id);
        string::append_utf8(&mut uri, b"/");
        string::append(&mut uri, reward_type_id);
        string::append_utf8(&mut uri, b"/metadata.json");

        uri
    }

    fun generate_reward_address(creator_address: address, collection_id: String, reward_id: String): address {
        token::create_token_address(
            &creator_address,
            &collection_id,
            &reward_id
        )
    }

    fun generate_collection_address(creator_address: address, collection_id: String): address {
        collection::create_collection_address(
            &creator_address,
            &collection_id,
        )
    }

    fun generate_organization_address(creator_address: address, organization_id: String): address {
        token::create_token_address(
            &creator_address,
            &string::utf8(ORGANIZATIONS_COLLECTION_NAME),
            &organization_id
        )
    }

    #[view]
    fun view_organization(creator_address: address, organization_id: String): NamelessOrganization acquires NamelessOrganization {
        let token_address = generate_organization_address(creator_address, organization_id);
        move_from<NamelessOrganization>(token_address)
    }

    #[view]
    fun view_collection(creator_address: address, collection_id: String): NamelessCollection acquires NamelessCollection {
        let collection_address = generate_collection_address(creator_address, collection_id);
        move_from<NamelessCollection>(collection_address)
    }

    #[view]
    fun view_reward(creator_address: address, collection_id: String, reward_id: String): NamelessReward acquires NamelessReward {
        let reward_address = generate_reward_address(creator_address, collection_id, reward_id);
        move_from<NamelessReward>(reward_address)
    }

    #[test_only]
    fun init_module_for_test(creator: &signer, aptos_framework: &signer) {
        account::create_account_for_test(signer::address_of(creator));
        init_module(creator);

        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::update_global_time_for_test(1691941413632);
    }

    #[test(account = @0xFA, user = @0xFF, aptos_framework = @aptos_framework)]
    #[expected_failure]
    fun test_auth(account: &signer, aptos_framework: &signer, user: &signer) acquires NamelessConfig {
        init_module_for_test(account, aptos_framework);
        aptos_account::create_account(signer::address_of(user));

        create_organization(
            user, string::utf8(b"ORG_ID"), string::utf8(b"ORG_NAME")
        );
    }

    #[test(account = @0x7a82477da5e3dc93eec06410198ae66371cc06e0665b9f97074198e85e67d53b, user = @0xFF, transfer_receiver = @0xFB, aptos_framework = @aptos_framework)]
    fun test_create_token(account: &signer, aptos_framework: &signer, user: &signer, transfer_receiver: address) acquires NamelessConfig, NamelessOrganization, NamelessCollection, NamelessToken {
        init_module_for_test(account, aptos_framework);

        create_organization(
            account, string::utf8(b"OR87c35334-d43c-4208-b8dd-7adeab94a6d5"), string::utf8(b"ORG_NAME")
        );

        let account_address = signer::address_of(account);
        let organization_address = generate_organization_address(account_address, string::utf8(b"OR87c35334-d43c-4208-b8dd-7adeab94a6d5"));
        assert!(object::is_object(organization_address), 400);
        print(&token::create_token_seed(&string::utf8(ORGANIZATIONS_COLLECTION_NAME), &string::utf8(b"OR87c35334-d43c-4208-b8dd-7adeab94a6d5")));
        print(&organization_address);
        update_organization_uri(account, object::address_to_object<NamelessOrganization>(organization_address));

        create_collection(
            account, object::address_to_object<NamelessOrganization>(organization_address), string::utf8(b"EVENT_ID"), string::utf8(b"A Test Collection"),50,1,2
        );

        let nameless_collection_address = generate_collection_address(account_address, string::utf8(b"COLLECTION_ID"));
        create_token(account, signer::address_of(user), object::address_to_object<NamelessCollection>(nameless_collection_address),  string::utf8(b"TT_ID"), string::utf8(b"TICKET_ID_1"), 1);
        create_token(account, signer::address_of(user), object::address_to_object<NamelessCollection>(nameless_collection_address),  string::utf8(b"TT_ID"), string::utf8(b"TICKET_ID_2"), 2);
        create_token(account, signer::address_of(user), object::address_to_object<NamelessCollection>(nameless_collection_address),  string::utf8(b"TT_ID"), string::utf8(b"TICKET_ID_3"),3);

        update_collection_start_date(account, object::address_to_object<NamelessCollection>(nameless_collection_address), 3);
        update_collection_end_date(account, object::address_to_object<NamelessCollection>(nameless_collection_address), 4);
        update_collection_uri(account, object::address_to_object<NamelessCollection>(nameless_collection_address));

        let nameless_token_address = generate_token_address(account_address, string::utf8(b"COLLECTION_ID"), string::utf8(b"TICKET_ID_1"));

        assert!(object::is_owner(object::address_to_object<NamelessToken>(nameless_token_address), signer::address_of(user)), error::permission_denied(ENOT_TOKEN_OWNER));

        transfer_token(account, transfer_receiver, object::address_to_object<NamelessToken>(nameless_token_address));
        assert!(object::is_owner(object::address_to_object<NamelessToken>(nameless_token_address), transfer_receiver), error::permission_denied(ENOT_TOKEN_OWNER));

        redeem_token(account, object::address_to_object<NamelessToken>(nameless_token_address));

        let nameless_reward = borrow_global<NamelessReward>(nameless_reward_address);
        assert!(nameless_reward.redeemed_at > 0, error::permission_denied(EINVALID_UPDATE));
    }
}