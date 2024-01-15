SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: heroku_ext; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA heroku_ext;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS '';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA heroku_ext;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: check_block_imported_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_block_imported_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
          BEGIN
            IF NEW.imported_at IS NOT NULL THEN
              IF EXISTS (
                SELECT 1
                FROM eth_blocks
                WHERE block_number < NEW.block_number
                  AND imported_at IS NULL
                LIMIT 1
              ) THEN
                RAISE EXCEPTION 'Previous block not yet imported';
              END IF;
            END IF;
            RETURN NEW;
          END;
          $$;


--
-- Name: check_block_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_block_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
          BEGIN
            IF NEW.is_genesis_block = false AND 
              NEW.block_number <> (SELECT MAX(block_number) + 1 FROM eth_blocks) THEN
              RAISE EXCEPTION 'Block number is not sequential';
            END IF;

            IF NEW.is_genesis_block = false AND 
              NEW.parent_blockhash <> (SELECT blockhash FROM eth_blocks WHERE block_number = NEW.block_number - 1) THEN
              RAISE EXCEPTION 'Parent block hash does not match the parent''s block hash';
            END IF;

            RETURN NEW;
          END;
          $$;


--
-- Name: check_block_order_on_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_block_order_on_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.imported_at IS NOT NULL AND NEW.state_hash IS NULL THEN
    RAISE EXCEPTION 'state_hash must be set when imported_at is set';
  END IF;

  IF NEW.is_genesis_block = false AND 
    NEW.parent_state_hash <> (SELECT state_hash FROM eth_blocks WHERE block_number = NEW.block_number - 1 AND imported_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Parent state hash does not match the state hash of the previous block';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: check_ethscription_order_and_sequence(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_ethscription_order_and_sequence() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
          BEGIN
            IF NEW.block_number < (SELECT MAX(block_number) FROM ethscriptions) OR
            (NEW.block_number = (SELECT MAX(block_number) FROM ethscriptions) AND NEW.transaction_index <= (SELECT MAX(transaction_index) FROM ethscriptions WHERE block_number = NEW.block_number)) THEN
              RAISE EXCEPTION 'Ethscriptions must be created in order';
            END IF;
            NEW.ethscription_number := (SELECT COALESCE(MAX(ethscription_number), -1) + 1 FROM ethscriptions);
            RETURN NEW;
          END;
          $$;


--
-- Name: delete_later_blocks(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_later_blocks() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
          BEGIN
            DELETE FROM eth_blocks WHERE block_number > OLD.block_number;
            RETURN OLD;
          END;
          $$;


--
-- Name: update_current_owner(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_current_owner() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
          DECLARE
            latest_ownership_version RECORD;
          BEGIN
            IF TG_OP = 'INSERT' THEN
              SELECT INTO latest_ownership_version *
              FROM ethscription_ownership_versions
              WHERE ethscription_transaction_hash = NEW.ethscription_transaction_hash
              ORDER BY block_number DESC, transaction_index DESC, transfer_index DESC
              LIMIT 1;

              UPDATE ethscriptions
              SET current_owner = latest_ownership_version.current_owner,
                  previous_owner = latest_ownership_version.previous_owner,
                  updated_at = NOW()
              WHERE transaction_hash = NEW.ethscription_transaction_hash;
            ELSIF TG_OP = 'DELETE' THEN
              SELECT INTO latest_ownership_version *
              FROM ethscription_ownership_versions
              WHERE ethscription_transaction_hash = OLD.ethscription_transaction_hash
                AND id != OLD.id
              ORDER BY block_number DESC, transaction_index DESC, transfer_index DESC
              LIMIT 1;

              UPDATE ethscriptions
              SET current_owner = latest_ownership_version.current_owner,
                  previous_owner = latest_ownership_version.previous_owner,
                  updated_at = NOW()
              WHERE transaction_hash = OLD.ethscription_transaction_hash;
            END IF;

            RETURN NULL;
          END;
          $$;


--
-- Name: update_total_supply(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_total_supply() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        UPDATE tokens
        SET total_supply = (
          SELECT COUNT(*) * mint_amount
          FROM token_items
          WHERE deploy_ethscription_transaction_hash = NEW.deploy_ethscription_transaction_hash
        )
        WHERE deploy_ethscription_transaction_hash = NEW.deploy_ethscription_transaction_hash;

        RETURN NEW;
      END;
      $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: delayed_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.delayed_jobs (
    id bigint NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    handler text NOT NULL,
    last_error text,
    run_at timestamp(6) without time zone,
    locked_at timestamp(6) without time zone,
    failed_at timestamp(6) without time zone,
    locked_by character varying,
    queue character varying,
    created_at timestamp(6) without time zone,
    updated_at timestamp(6) without time zone
);


--
-- Name: delayed_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.delayed_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: delayed_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.delayed_jobs_id_seq OWNED BY public.delayed_jobs.id;


--
-- Name: eth_blocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eth_blocks (
    id bigint NOT NULL,
    block_number bigint NOT NULL,
    "timestamp" bigint NOT NULL,
    blockhash character varying NOT NULL,
    parent_blockhash character varying NOT NULL,
    imported_at timestamp(6) without time zone,
    state_hash character varying,
    parent_state_hash character varying,
    is_genesis_block boolean NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_1c105acdac CHECK (((parent_blockhash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_319237323b CHECK (((state_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_7126b7c9d3 CHECK (((parent_state_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_7e9881ece2 CHECK (((blockhash)::text ~ '^0x[a-f0-9]{64}$'::text))
);


--
-- Name: eth_blocks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.eth_blocks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: eth_blocks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.eth_blocks_id_seq OWNED BY public.eth_blocks.id;


--
-- Name: eth_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eth_transactions (
    id bigint NOT NULL,
    transaction_hash character varying NOT NULL,
    block_number bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    block_blockhash character varying NOT NULL,
    from_address character varying NOT NULL,
    to_address character varying,
    input text NOT NULL,
    transaction_index bigint NOT NULL,
    status integer,
    logs jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_contract_address character varying,
    gas_price numeric NOT NULL,
    gas_used bigint NOT NULL,
    transaction_fee numeric NOT NULL,
    value numeric NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_37ed5d6017 CHECK (((to_address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_4250f2c315 CHECK (((block_blockhash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_9cdbd3b1ad CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_a4d3f41974 CHECK (((from_address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_d460e80110 CHECK (((created_contract_address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT contract_to_check CHECK ((((created_contract_address IS NULL) AND (to_address IS NOT NULL)) OR ((created_contract_address IS NOT NULL) AND (to_address IS NULL)))),
    CONSTRAINT status_check CHECK ((((block_number <= 4370000) AND (status IS NULL)) OR ((block_number > 4370000) AND (status = 1))))
);


--
-- Name: eth_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.eth_transactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: eth_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.eth_transactions_id_seq OWNED BY public.eth_transactions.id;


--
-- Name: ethscription_ownership_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ethscription_ownership_versions (
    id bigint NOT NULL,
    transaction_hash character varying NOT NULL,
    ethscription_transaction_hash character varying NOT NULL,
    transfer_index bigint NOT NULL,
    block_number bigint NOT NULL,
    block_blockhash character varying NOT NULL,
    transaction_index bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    current_owner character varying NOT NULL,
    previous_owner character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_0401bc8d3b CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_073cb8a4e9 CHECK (((current_owner)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_3c5af30513 CHECK (((block_blockhash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_b5b3ce91a9 CHECK (((previous_owner)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_f8a9e94d3c CHECK (((ethscription_transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text))
);


--
-- Name: ethscription_ownership_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ethscription_ownership_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ethscription_ownership_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ethscription_ownership_versions_id_seq OWNED BY public.ethscription_ownership_versions.id;


--
-- Name: ethscription_transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ethscription_transfers (
    id bigint NOT NULL,
    ethscription_transaction_hash character varying NOT NULL,
    transaction_hash character varying NOT NULL,
    from_address character varying NOT NULL,
    to_address character varying NOT NULL,
    block_number bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    block_blockhash character varying NOT NULL,
    event_log_index bigint,
    transfer_index bigint NOT NULL,
    transaction_index bigint NOT NULL,
    enforced_previous_owner character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_1c9802c481 CHECK (((enforced_previous_owner)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_448edb0194 CHECK (((block_blockhash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_7959eeae60 CHECK (((from_address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_7f4ef1507d CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_a138317254 CHECK (((to_address)::text ~ '^0x[a-f0-9]{40}$'::text))
);


--
-- Name: ethscription_transfers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ethscription_transfers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ethscription_transfers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ethscription_transfers_id_seq OWNED BY public.ethscription_transfers.id;


--
-- Name: ethscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ethscriptions (
    id bigint NOT NULL,
    transaction_hash character varying NOT NULL,
    block_number bigint NOT NULL,
    transaction_index bigint NOT NULL,
    block_timestamp bigint NOT NULL,
    block_blockhash character varying NOT NULL,
    event_log_index bigint,
    ethscription_number bigint NOT NULL,
    creator character varying NOT NULL,
    initial_owner character varying NOT NULL,
    current_owner character varying NOT NULL,
    previous_owner character varying NOT NULL,
    content_uri text NOT NULL,
    content_sha character varying NOT NULL,
    esip6 boolean NOT NULL,
    mimetype character varying(1000) NOT NULL,
    media_type character varying(1000) NOT NULL,
    mime_subtype character varying(1000) NOT NULL,
    gas_price numeric NOT NULL,
    gas_used bigint NOT NULL,
    transaction_fee numeric NOT NULL,
    value numeric NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_52497428f2 CHECK (((previous_owner)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_528fcbfbaa CHECK (((content_sha)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_6f8922831e CHECK (((current_owner)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_788fa87594 CHECK (((block_blockhash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_84591e2730 CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_b577b97822 CHECK (((creator)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_df21fdbe02 CHECK (((initial_owner)::text ~ '^0x[a-f0-9]{40}$'::text))
);


--
-- Name: ethscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ethscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ethscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ethscriptions_id_seq OWNED BY public.ethscriptions.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: token_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.token_items (
    id bigint NOT NULL,
    ethscription_transaction_hash character varying NOT NULL,
    deploy_ethscription_transaction_hash character varying NOT NULL,
    token_item_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_37f43f9259 CHECK (((deploy_ethscription_transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_4a492d2c53 CHECK ((token_item_id > 0)),
    CONSTRAINT chk_rails_4e045edbe2 CHECK (((ethscription_transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text))
);


--
-- Name: token_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.token_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: token_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.token_items_id_seq OWNED BY public.token_items.id;


--
-- Name: tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tokens (
    id bigint NOT NULL,
    deploy_ethscription_transaction_hash character varying NOT NULL,
    deploy_block_number bigint NOT NULL,
    deploy_transaction_index bigint NOT NULL,
    protocol character varying NOT NULL,
    tick character varying NOT NULL,
    max_supply bigint NOT NULL,
    total_supply bigint DEFAULT 0 NOT NULL,
    mint_amount bigint NOT NULL,
    decimals integer NOT NULL,
    versioned_balances jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_3458514b65 CHECK (((deploy_ethscription_transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_49b9979508 CHECK (((protocol)::text = lower((protocol)::text))),
    CONSTRAINT chk_rails_53ece3f224 CHECK ((total_supply <= max_supply)),
    CONSTRAINT chk_rails_596664ed3b CHECK ((total_supply >= 0)),
    CONSTRAINT chk_rails_656ef5c2e5 CHECK (((tick)::text ~ '^[a-zA-Z0-9]{1,18}$'::text)),
    CONSTRAINT chk_rails_b41faadd12 CHECK ((mint_amount > 0)),
    CONSTRAINT chk_rails_d17eb6ceff CHECK (((decimals > 0) AND (decimals <= 18))),
    CONSTRAINT chk_rails_d3c8f232c1 CHECK (((protocol)::text ~ '^[a-z0-9-]{1,18}$'::text)),
    CONSTRAINT chk_rails_e954152758 CHECK ((max_supply > 0))
);


--
-- Name: tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tokens_id_seq OWNED BY public.tokens.id;


--
-- Name: delayed_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delayed_jobs ALTER COLUMN id SET DEFAULT nextval('public.delayed_jobs_id_seq'::regclass);


--
-- Name: eth_blocks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_blocks ALTER COLUMN id SET DEFAULT nextval('public.eth_blocks_id_seq'::regclass);


--
-- Name: eth_transactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_transactions ALTER COLUMN id SET DEFAULT nextval('public.eth_transactions_id_seq'::regclass);


--
-- Name: ethscription_ownership_versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscription_ownership_versions ALTER COLUMN id SET DEFAULT nextval('public.ethscription_ownership_versions_id_seq'::regclass);


--
-- Name: ethscription_transfers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscription_transfers ALTER COLUMN id SET DEFAULT nextval('public.ethscription_transfers_id_seq'::regclass);


--
-- Name: ethscriptions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscriptions ALTER COLUMN id SET DEFAULT nextval('public.ethscriptions_id_seq'::regclass);


--
-- Name: token_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_items ALTER COLUMN id SET DEFAULT nextval('public.token_items_id_seq'::regclass);


--
-- Name: tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens ALTER COLUMN id SET DEFAULT nextval('public.tokens_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: delayed_jobs delayed_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.delayed_jobs
    ADD CONSTRAINT delayed_jobs_pkey PRIMARY KEY (id);


--
-- Name: eth_blocks eth_blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_blocks
    ADD CONSTRAINT eth_blocks_pkey PRIMARY KEY (id);


--
-- Name: eth_transactions eth_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_transactions
    ADD CONSTRAINT eth_transactions_pkey PRIMARY KEY (id);


--
-- Name: ethscription_ownership_versions ethscription_ownership_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscription_ownership_versions
    ADD CONSTRAINT ethscription_ownership_versions_pkey PRIMARY KEY (id);


--
-- Name: ethscription_transfers ethscription_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscription_transfers
    ADD CONSTRAINT ethscription_transfers_pkey PRIMARY KEY (id);


--
-- Name: ethscriptions ethscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscriptions
    ADD CONSTRAINT ethscriptions_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: token_items token_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_items
    ADD CONSTRAINT token_items_pkey PRIMARY KEY (id);


--
-- Name: tokens tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT tokens_pkey PRIMARY KEY (id);


--
-- Name: delayed_jobs_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX delayed_jobs_priority ON public.delayed_jobs USING btree (priority, run_at);


--
-- Name: idx_on_block_number_transaction_index_event_log_ind_94b2c4b953; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_block_number_transaction_index_event_log_ind_94b2c4b953 ON public.ethscription_transfers USING btree (block_number, transaction_index, event_log_index);


--
-- Name: idx_on_block_number_transaction_index_transfer_inde_8090d24b9e; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_block_number_transaction_index_transfer_inde_8090d24b9e ON public.ethscription_ownership_versions USING btree (block_number, transaction_index, transfer_index);


--
-- Name: idx_on_block_number_transaction_index_transfer_inde_fc9ee59957; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_block_number_transaction_index_transfer_inde_fc9ee59957 ON public.ethscription_transfers USING btree (block_number, transaction_index, transfer_index);


--
-- Name: idx_on_current_owner_previous_owner_7bb4bbf3cf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_current_owner_previous_owner_7bb4bbf3cf ON public.ethscription_ownership_versions USING btree (current_owner, previous_owner);


--
-- Name: idx_on_deploy_block_number_deploy_transaction_index_16cfcbe277; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_deploy_block_number_deploy_transaction_index_16cfcbe277 ON public.tokens USING btree (deploy_block_number, deploy_transaction_index);


--
-- Name: idx_on_deploy_ethscription_transaction_hash_token_i_8afe3c6082; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_deploy_ethscription_transaction_hash_token_i_8afe3c6082 ON public.token_items USING btree (deploy_ethscription_transaction_hash, token_item_id);


--
-- Name: idx_on_ethscription_transaction_hash_deploy_ethscri_5f2ffeede2; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_ethscription_transaction_hash_deploy_ethscri_5f2ffeede2 ON public.token_items USING btree (ethscription_transaction_hash, deploy_ethscription_transaction_hash, token_item_id);


--
-- Name: idx_on_ethscription_transaction_hash_e9e1b526f9; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_ethscription_transaction_hash_e9e1b526f9 ON public.ethscription_ownership_versions USING btree (ethscription_transaction_hash);


--
-- Name: idx_on_transaction_hash_event_log_index_c192a81bef; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_transaction_hash_event_log_index_c192a81bef ON public.ethscription_transfers USING btree (transaction_hash, event_log_index);


--
-- Name: idx_on_transaction_hash_transfer_index_4389678e0a; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_transaction_hash_transfer_index_4389678e0a ON public.ethscription_transfers USING btree (transaction_hash, transfer_index);


--
-- Name: idx_on_transaction_hash_transfer_index_b79931daa1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_transaction_hash_transfer_index_b79931daa1 ON public.ethscription_ownership_versions USING btree (transaction_hash, transfer_index);


--
-- Name: index_eth_blocks_on_block_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_eth_blocks_on_block_number ON public.eth_blocks USING btree (block_number);


--
-- Name: index_eth_blocks_on_blockhash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_eth_blocks_on_blockhash ON public.eth_blocks USING btree (blockhash);


--
-- Name: index_eth_blocks_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_blocks_on_created_at ON public.eth_blocks USING btree (created_at);


--
-- Name: index_eth_blocks_on_imported_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_blocks_on_imported_at ON public.eth_blocks USING btree (imported_at);


--
-- Name: index_eth_blocks_on_imported_at_and_block_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_blocks_on_imported_at_and_block_number ON public.eth_blocks USING btree (imported_at, block_number);


--
-- Name: index_eth_blocks_on_parent_blockhash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_eth_blocks_on_parent_blockhash ON public.eth_blocks USING btree (parent_blockhash);


--
-- Name: index_eth_blocks_on_parent_state_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_eth_blocks_on_parent_state_hash ON public.eth_blocks USING btree (parent_state_hash);


--
-- Name: index_eth_blocks_on_state_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_eth_blocks_on_state_hash ON public.eth_blocks USING btree (state_hash);


--
-- Name: index_eth_blocks_on_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_eth_blocks_on_timestamp ON public.eth_blocks USING btree ("timestamp");


--
-- Name: index_eth_blocks_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_blocks_on_updated_at ON public.eth_blocks USING btree (updated_at);


--
-- Name: index_eth_transactions_on_block_blockhash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_transactions_on_block_blockhash ON public.eth_transactions USING btree (block_blockhash);


--
-- Name: index_eth_transactions_on_block_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_transactions_on_block_number ON public.eth_transactions USING btree (block_number);


--
-- Name: index_eth_transactions_on_block_number_and_transaction_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_eth_transactions_on_block_number_and_transaction_index ON public.eth_transactions USING btree (block_number, transaction_index);


--
-- Name: index_eth_transactions_on_block_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_transactions_on_block_timestamp ON public.eth_transactions USING btree (block_timestamp);


--
-- Name: index_eth_transactions_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_transactions_on_created_at ON public.eth_transactions USING btree (created_at);


--
-- Name: index_eth_transactions_on_from_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_transactions_on_from_address ON public.eth_transactions USING btree (from_address);


--
-- Name: index_eth_transactions_on_logs; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_transactions_on_logs ON public.eth_transactions USING gin (logs);


--
-- Name: index_eth_transactions_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_transactions_on_status ON public.eth_transactions USING btree (status);


--
-- Name: index_eth_transactions_on_to_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_transactions_on_to_address ON public.eth_transactions USING btree (to_address);


--
-- Name: index_eth_transactions_on_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_eth_transactions_on_transaction_hash ON public.eth_transactions USING btree (transaction_hash);


--
-- Name: index_eth_transactions_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_transactions_on_updated_at ON public.eth_transactions USING btree (updated_at);


--
-- Name: index_ethscription_ownership_versions_on_block_blockhash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_ownership_versions_on_block_blockhash ON public.ethscription_ownership_versions USING btree (block_blockhash);


--
-- Name: index_ethscription_ownership_versions_on_block_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_ownership_versions_on_block_number ON public.ethscription_ownership_versions USING btree (block_number);


--
-- Name: index_ethscription_ownership_versions_on_block_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_ownership_versions_on_block_timestamp ON public.ethscription_ownership_versions USING btree (block_timestamp);


--
-- Name: index_ethscription_ownership_versions_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_ownership_versions_on_created_at ON public.ethscription_ownership_versions USING btree (created_at);


--
-- Name: index_ethscription_ownership_versions_on_current_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_ownership_versions_on_current_owner ON public.ethscription_ownership_versions USING btree (current_owner);


--
-- Name: index_ethscription_ownership_versions_on_previous_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_ownership_versions_on_previous_owner ON public.ethscription_ownership_versions USING btree (previous_owner);


--
-- Name: index_ethscription_ownership_versions_on_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_ownership_versions_on_transaction_hash ON public.ethscription_ownership_versions USING btree (transaction_hash);


--
-- Name: index_ethscription_ownership_versions_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_ownership_versions_on_updated_at ON public.ethscription_ownership_versions USING btree (updated_at);


--
-- Name: index_ethscription_transfers_on_block_blockhash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_transfers_on_block_blockhash ON public.ethscription_transfers USING btree (block_blockhash);


--
-- Name: index_ethscription_transfers_on_block_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_transfers_on_block_number ON public.ethscription_transfers USING btree (block_number);


--
-- Name: index_ethscription_transfers_on_block_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_transfers_on_block_timestamp ON public.ethscription_transfers USING btree (block_timestamp);


--
-- Name: index_ethscription_transfers_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_transfers_on_created_at ON public.ethscription_transfers USING btree (created_at);


--
-- Name: index_ethscription_transfers_on_enforced_previous_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_transfers_on_enforced_previous_owner ON public.ethscription_transfers USING btree (enforced_previous_owner);


--
-- Name: index_ethscription_transfers_on_ethscription_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_transfers_on_ethscription_transaction_hash ON public.ethscription_transfers USING btree (ethscription_transaction_hash);


--
-- Name: index_ethscription_transfers_on_from_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_transfers_on_from_address ON public.ethscription_transfers USING btree (from_address);


--
-- Name: index_ethscription_transfers_on_to_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_transfers_on_to_address ON public.ethscription_transfers USING btree (to_address);


--
-- Name: index_ethscription_transfers_on_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_transfers_on_transaction_hash ON public.ethscription_transfers USING btree (transaction_hash);


--
-- Name: index_ethscription_transfers_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscription_transfers_on_updated_at ON public.ethscription_transfers USING btree (updated_at);


--
-- Name: index_ethscriptions_on_block_blockhash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_block_blockhash ON public.ethscriptions USING btree (block_blockhash);


--
-- Name: index_ethscriptions_on_block_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_block_number ON public.ethscriptions USING btree (block_number);


--
-- Name: index_ethscriptions_on_block_number_and_transaction_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ethscriptions_on_block_number_and_transaction_index ON public.ethscriptions USING btree (block_number, transaction_index);


--
-- Name: index_ethscriptions_on_block_timestamp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_block_timestamp ON public.ethscriptions USING btree (block_timestamp);


--
-- Name: index_ethscriptions_on_content_sha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_content_sha ON public.ethscriptions USING btree (content_sha);


--
-- Name: index_ethscriptions_on_content_sha_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ethscriptions_on_content_sha_unique ON public.ethscriptions USING btree (content_sha) WHERE (esip6 = false);


--
-- Name: index_ethscriptions_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_created_at ON public.ethscriptions USING btree (created_at);


--
-- Name: index_ethscriptions_on_creator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_creator ON public.ethscriptions USING btree (creator);


--
-- Name: index_ethscriptions_on_current_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_current_owner ON public.ethscriptions USING btree (current_owner);


--
-- Name: index_ethscriptions_on_esip6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_esip6 ON public.ethscriptions USING btree (esip6);


--
-- Name: index_ethscriptions_on_ethscription_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ethscriptions_on_ethscription_number ON public.ethscriptions USING btree (ethscription_number);


--
-- Name: index_ethscriptions_on_initial_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_initial_owner ON public.ethscriptions USING btree (initial_owner);


--
-- Name: index_ethscriptions_on_media_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_media_type ON public.ethscriptions USING btree (media_type);


--
-- Name: index_ethscriptions_on_mime_subtype; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_mime_subtype ON public.ethscriptions USING btree (mime_subtype);


--
-- Name: index_ethscriptions_on_mimetype; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_mimetype ON public.ethscriptions USING btree (mimetype);


--
-- Name: index_ethscriptions_on_previous_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_previous_owner ON public.ethscriptions USING btree (previous_owner);


--
-- Name: index_ethscriptions_on_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ethscriptions_on_transaction_hash ON public.ethscriptions USING btree (transaction_hash);


--
-- Name: index_ethscriptions_on_transaction_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_transaction_index ON public.ethscriptions USING btree (transaction_index);


--
-- Name: index_ethscriptions_on_updated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_updated_at ON public.ethscriptions USING btree (updated_at);


--
-- Name: index_token_items_on_ethscription_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_token_items_on_ethscription_transaction_hash ON public.token_items USING btree (ethscription_transaction_hash);


--
-- Name: index_tokens_on_deploy_ethscription_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tokens_on_deploy_ethscription_transaction_hash ON public.tokens USING btree (deploy_ethscription_transaction_hash);


--
-- Name: index_tokens_on_protocol; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tokens_on_protocol ON public.tokens USING btree (protocol);


--
-- Name: index_tokens_on_protocol_and_tick; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tokens_on_protocol_and_tick ON public.tokens USING btree (protocol, tick);


--
-- Name: eth_blocks check_block_imported_at_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER check_block_imported_at_trigger BEFORE UPDATE OF imported_at ON public.eth_blocks FOR EACH ROW EXECUTE FUNCTION public.check_block_imported_at();


--
-- Name: eth_blocks trigger_check_block_order; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_check_block_order BEFORE INSERT ON public.eth_blocks FOR EACH ROW EXECUTE FUNCTION public.check_block_order();


--
-- Name: eth_blocks trigger_check_block_order_on_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_check_block_order_on_update BEFORE UPDATE OF imported_at ON public.eth_blocks FOR EACH ROW WHEN ((new.imported_at IS NOT NULL)) EXECUTE FUNCTION public.check_block_order_on_update();


--
-- Name: ethscriptions trigger_check_ethscription_order_and_sequence; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_check_ethscription_order_and_sequence BEFORE INSERT ON public.ethscriptions FOR EACH ROW EXECUTE FUNCTION public.check_ethscription_order_and_sequence();


--
-- Name: eth_blocks trigger_delete_later_blocks; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_delete_later_blocks AFTER DELETE ON public.eth_blocks FOR EACH ROW EXECUTE FUNCTION public.delete_later_blocks();


--
-- Name: ethscription_ownership_versions update_current_owner; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_current_owner AFTER INSERT OR DELETE ON public.ethscription_ownership_versions FOR EACH ROW EXECUTE FUNCTION public.update_current_owner();


--
-- Name: token_items update_total_supply_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_total_supply_trigger AFTER DELETE ON public.token_items FOR EACH ROW EXECUTE FUNCTION public.update_total_supply();


--
-- Name: ethscriptions fk_rails_104cee2b3d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscriptions
    ADD CONSTRAINT fk_rails_104cee2b3d FOREIGN KEY (block_number) REFERENCES public.eth_blocks(block_number) ON DELETE CASCADE;


--
-- Name: tokens fk_rails_1c09e75f12; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tokens
    ADD CONSTRAINT fk_rails_1c09e75f12 FOREIGN KEY (deploy_ethscription_transaction_hash) REFERENCES public.ethscriptions(transaction_hash) ON DELETE CASCADE;


--
-- Name: ethscriptions fk_rails_2accd8a448; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscriptions
    ADD CONSTRAINT fk_rails_2accd8a448 FOREIGN KEY (transaction_hash) REFERENCES public.eth_transactions(transaction_hash) ON DELETE CASCADE;


--
-- Name: ethscription_transfers fk_rails_2fe933886e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscription_transfers
    ADD CONSTRAINT fk_rails_2fe933886e FOREIGN KEY (transaction_hash) REFERENCES public.eth_transactions(transaction_hash) ON DELETE CASCADE;


--
-- Name: ethscription_transfers fk_rails_479ac03c16; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscription_transfers
    ADD CONSTRAINT fk_rails_479ac03c16 FOREIGN KEY (ethscription_transaction_hash) REFERENCES public.ethscriptions(transaction_hash) ON DELETE CASCADE;


--
-- Name: eth_transactions fk_rails_4937ed3300; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_transactions
    ADD CONSTRAINT fk_rails_4937ed3300 FOREIGN KEY (block_number) REFERENCES public.eth_blocks(block_number) ON DELETE CASCADE;


--
-- Name: ethscription_ownership_versions fk_rails_8808aa138a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscription_ownership_versions
    ADD CONSTRAINT fk_rails_8808aa138a FOREIGN KEY (ethscription_transaction_hash) REFERENCES public.ethscriptions(transaction_hash) ON DELETE CASCADE;


--
-- Name: token_items fk_rails_8d58f29890; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_items
    ADD CONSTRAINT fk_rails_8d58f29890 FOREIGN KEY (deploy_ethscription_transaction_hash) REFERENCES public.tokens(deploy_ethscription_transaction_hash) ON DELETE CASCADE;


--
-- Name: ethscription_transfers fk_rails_b68511af4b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscription_transfers
    ADD CONSTRAINT fk_rails_b68511af4b FOREIGN KEY (block_number) REFERENCES public.eth_blocks(block_number) ON DELETE CASCADE;


--
-- Name: ethscription_ownership_versions fk_rails_e95d97c83e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscription_ownership_versions
    ADD CONSTRAINT fk_rails_e95d97c83e FOREIGN KEY (block_number) REFERENCES public.eth_blocks(block_number) ON DELETE CASCADE;


--
-- Name: ethscription_ownership_versions fk_rails_ed1fdc1619; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscription_ownership_versions
    ADD CONSTRAINT fk_rails_ed1fdc1619 FOREIGN KEY (transaction_hash) REFERENCES public.eth_transactions(transaction_hash) ON DELETE CASCADE;


--
-- Name: token_items fk_rails_ffdbb769e4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_items
    ADD CONSTRAINT fk_rails_ffdbb769e4 FOREIGN KEY (ethscription_transaction_hash) REFERENCES public.ethscriptions(transaction_hash) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20240115192312'),
('20240115151119'),
('20240115144930'),
('20231216215348'),
('20231216213103'),
('20231216164707'),
('20231216163233'),
('20231216161930');

