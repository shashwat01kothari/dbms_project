--
-- PostgreSQL database dump
--

-- Dumped from database version 17.0
-- Dumped by pg_dump version 17.0

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: change_booking_time(integer, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.change_booking_time(p_booking_id integer, p_new_booking_time timestamp without time zone) RETURNS text
    LANGUAGE plpgsql
    AS $$
    DECLARE
        v_ground_id INT;
        v_is_available BOOLEAN;
    BEGIN
        SELECT ground_id INTO v_ground_id FROM bookings WHERE booking_id = p_booking_id;

        IF NOT FOUND THEN
            RETURN 'Booking ID not found.';
        END IF;
        SELECT is_available INTO v_is_available
        FROM availability
        WHERE ground_id = v_ground_id AND time_slot = p_new_booking_time AND is_available = TRUE;

        IF NOT v_is_available THEN
            RETURN 'The selected time slot is not available.';
        END IF;

        UPDATE bookings
        SET booking_time = p_new_booking_time
        WHERE booking_id = p_booking_id;


        UPDATE availability
        SET is_available = FALSE
        WHERE ground_id = v_ground_id AND time_slot = p_new_booking_time;

        RETURN 'Booking time successfully updated.';
    END;
    $$;


ALTER FUNCTION public.change_booking_time(p_booking_id integer, p_new_booking_time timestamp without time zone) OWNER TO postgres;

--
-- Name: check_and_book(integer, integer, date, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_and_book(p_user_id integer, p_ground_id integer, p_booking_date date, p_time_slot character varying) RETURNS TABLE(p_booking_id integer, p_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    p_is_available BOOLEAN;
    p_user_balance NUMERIC(10, 2);  -- changed to NUMERIC for currency
    p_wallet_id INT;
    p_creator_id INT;
BEGIN
    -- Check availability for the specified ground, date, and time slot
    SELECT a.is_available INTO p_is_available
    FROM availability a
    WHERE a.ground_id = p_ground_id 
    AND a.date = p_booking_date 
    AND a.time_slot = p_time_slot;

    -- If the ground is not available, return an error message
    IF p_is_available IS NOT TRUE THEN
        RETURN QUERY SELECT NULL::INTEGER, 'The ground is not available for the selected date and time slot.'::TEXT;
        RETURN;
    END IF;

    -- Check the user's balance to ensure they have enough funds
    SELECT balance, wallet_id INTO p_user_balance, p_wallet_id
    FROM wallet
    WHERE user_id = p_user_id;

    -- If the user doesn't have a wallet or insufficient balance, return an error message
    IF p_wallet_id IS NULL THEN
        RETURN QUERY SELECT NULL::INTEGER, 'User wallet not found.'::TEXT;
        RETURN;
    ELSIF p_user_balance < 100 THEN
        RETURN QUERY SELECT NULL::INTEGER, 'Insufficient balance to complete the booking.'::TEXT;
        RETURN;
    END IF;

    -- Insert the booking and retrieve the booking_id
    INSERT INTO bookings (ground_id, user_id, booking_date, time_slot)
    VALUES (p_ground_id, p_user_id, p_booking_date, p_time_slot)
    RETURNING booking_id INTO p_booking_id;

    -- Update availability to mark as booked
    UPDATE availability
    SET is_available = FALSE
    WHERE ground_id = p_ground_id 
    AND date = p_booking_date 
    AND time_slot = p_time_slot;

    -- Deduct 100 from the user's balance
    UPDATE wallet
    SET balance = balance - 100
    WHERE user_id = p_user_id;

    -- Insert transaction record into wallet_transactions for the user
    INSERT INTO wallet_transactions (
        wallet_id, 
        transaction_type, 
        amount, 
        description
    ) 
    VALUES (
        p_wallet_id, 
        'debit', 
        100, 
        'Booking payment for ground ID ' || p_ground_id || ' on ' || p_booking_date || ' for ' || p_time_slot
    );

    -- Update wallet of user_id 13 by adding 20
    UPDATE wallet
    SET balance = balance + 20
    WHERE user_id = 13;

    -- Find the creator_id of the ground and update their wallet by adding 90
    SELECT creator_id INTO p_creator_id
    FROM grounds
    WHERE ground_id = p_ground_id;

    IF p_creator_id IS NOT NULL THEN
        UPDATE wallet
        SET balance = balance + 90
        WHERE user_id = p_creator_id;

        -- Insert transaction record for the creator
        INSERT INTO wallet_transactions (
            wallet_id, 
            transaction_type, 
            amount, 
            description
        ) 
        VALUES (
            (SELECT wallet_id FROM wallet WHERE user_id = p_creator_id), 
            'credit', 
            90, 
            'Booking payment for ground ID ' || p_ground_id || ' on ' || p_booking_date || ' for ' || p_time_slot
        );
    END IF;

    -- Return the booking_id and a success message
    RETURN QUERY 
    SELECT p_booking_id::INTEGER, 'Booking confirmed successfully. Balance has been updated and transaction recorded.'::TEXT;
END;
$$;


ALTER FUNCTION public.check_and_book(p_user_id integer, p_ground_id integer, p_booking_date date, p_time_slot character varying) OWNER TO postgres;

--
-- Name: check_and_book(integer, integer, character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_and_book(p_user_id integer, p_ground_id integer, p_booking_date character varying, p_time_slot character varying) RETURNS TABLE(p_booking_id integer, p_message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    p_is_available BOOLEAN;
    p_user_balance NUMERIC(10, 2);  -- changed to NUMERIC for currency
    p_wallet_id INT;
    p_creator_id INT;
    p_booking_date_converted DATE;  -- Add a new variable to store the converted date
BEGIN
    -- Convert p_booking_date to a SQL-compatible DATE type
    p_booking_date_converted := TO_DATE(p_booking_date, 'YYYY-MM-DD');  -- Adjust the format based on your string format

    -- Check availability for the specified ground, date, and time slot
    SELECT a.is_available INTO p_is_available
    FROM availability a
    WHERE a.ground_id = p_ground_id 
    AND a.date = p_booking_date_converted  -- Use the converted date
    AND a.time_slot = p_time_slot;

    -- If the ground is not available, return an error message
    IF p_is_available IS NOT TRUE THEN
        RETURN QUERY SELECT NULL::INTEGER, 'The ground is not available for the selected date and time slot.'::TEXT;
        RETURN;
    END IF;

    -- Check the user's balance to ensure they have enough funds
    SELECT balance, wallet_id INTO p_user_balance, p_wallet_id
    FROM wallet
    WHERE user_id = p_user_id;

    -- If the user doesn't have a wallet or insufficient balance, return an error message
    IF p_wallet_id IS NULL THEN
        RETURN QUERY SELECT NULL::INTEGER, 'User wallet not found.'::TEXT;
        RETURN;
    ELSIF p_user_balance < 100 THEN
        RETURN QUERY SELECT NULL::INTEGER, 'Insufficient balance to complete the booking.'::TEXT;
        RETURN;
    END IF;

    -- Insert the booking and retrieve the booking_id
    INSERT INTO bookings (ground_id, user_id, booking_date, time_slot)
    VALUES (p_ground_id, p_user_id, p_booking_date_converted, p_time_slot)  -- Use the converted date
    RETURNING booking_id INTO p_booking_id;

    -- Update availability to mark as booked
    UPDATE availability
    SET is_available = FALSE
    WHERE ground_id = p_ground_id 
    AND date = p_booking_date_converted  -- Use the converted date
    AND time_slot = p_time_slot;

    -- Deduct 100 from the user's balance
    UPDATE wallet
    SET balance = balance - 100
    WHERE user_id = p_user_id;

    -- Insert transaction record into wallet_transactions for the user
    INSERT INTO wallet_transactions (
        wallet_id, 
        transaction_type, 
        amount, 
        description
    ) 
    VALUES (
        p_wallet_id, 
        'debit', 
        100, 
        'Booking payment for ground ID ' || p_ground_id || ' on ' || p_booking_date_converted || ' for ' || p_time_slot
    );

    -- Update wallet of user_id 13 by adding 20
    UPDATE wallet
    SET balance = balance + 20
    WHERE user_id = 13;

    -- Find the creator_id of the ground and update their wallet by adding 90
    SELECT creator_id INTO p_creator_id
    FROM grounds
    WHERE ground_id = p_ground_id;

    IF p_creator_id IS NOT NULL THEN
        UPDATE wallet
        SET balance = balance + 90
        WHERE user_id = p_creator_id;

        -- Insert transaction record for the creator
        INSERT INTO wallet_transactions (
            wallet_id, 
            transaction_type, 
            amount, 
            description
        ) 
        VALUES (
            (SELECT wallet_id FROM wallet WHERE user_id = p_creator_id), 
            'credit', 
            90, 
            'Booking payment for ground ID ' || p_ground_id || ' on ' || p_booking_date_converted || ' for ' || p_time_slot
        );
    END IF;

    -- Return the booking_id and a success message
    RETURN QUERY 
    SELECT p_booking_id::INTEGER, 'Booking confirmed successfully. Balance has been updated and transaction recorded.'::TEXT;
END;
$$;


ALTER FUNCTION public.check_and_book(p_user_id integer, p_ground_id integer, p_booking_date character varying, p_time_slot character varying) OWNER TO postgres;

--
-- Name: check_and_book_ground(integer, integer, date, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_and_book_ground(user_id integer, ground_id integer, booking_date date, time_slot character varying) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    is_available BOOLEAN;
BEGIN
    -- Check availability for the specified ground, date, and time slot
    SELECT a.is_available INTO is_available
    FROM availability a
    WHERE a.ground_id = ground_id 
      AND a.date = booking_date 
      AND a.time_slot = time_slot;

    -- If the ground is not available, return an error message
    IF is_available IS NOT TRUE THEN
        RETURN 'The ground is not available for the selected date and time slot.';
    END IF;

    -- If available, insert the booking
    INSERT INTO bookings (ground_id, user_id, booking_date, time_slot)
    VALUES (ground_id, user_id, booking_date, time_slot);

    -- Update availability to mark as booked
    UPDATE availability
    SET is_available = FALSE
    WHERE ground_id = ground_id 
      AND date = booking_date 
      AND time_slot = time_slot;

    RETURN 'Booking confirmed successfully.';
END;
$$;


ALTER FUNCTION public.check_and_book_ground(user_id integer, ground_id integer, booking_date date, time_slot character varying) OWNER TO postgres;

--
-- Name: generate_receipt(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.generate_receipt() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
        booking_total NUMERIC(10, 2);
    BEGIN
        
        booking_total := 100.00;  

        -- Insert into the receipts table
        INSERT INTO receipts (booking_id, user_id, ground_id, total_amount)
        VALUES (
            NEW.booking_id,            
            NEW.user_id,               
            NEW.ground_id,             
            booking_total             
        );

        RETURN NEW;
    END;
    $$;


ALTER FUNCTION public.generate_receipt() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: availability; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.availability (
    availability_id integer NOT NULL,
    ground_id integer,
    date date NOT NULL,
    time_slot character varying(20) NOT NULL,
    is_available boolean DEFAULT true
);


ALTER TABLE public.availability OWNER TO postgres;

--
-- Name: availability_availability_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.availability_availability_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.availability_availability_id_seq OWNER TO postgres;

--
-- Name: availability_availability_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.availability_availability_id_seq OWNED BY public.availability.availability_id;


--
-- Name: bookings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bookings (
    booking_id integer NOT NULL,
    ground_id integer,
    user_id integer NOT NULL,
    booking_date date NOT NULL,
    time_slot character varying(20) NOT NULL,
    booking_timestamp timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    status character varying(20) DEFAULT 'Confirmed'::character varying
);


ALTER TABLE public.bookings OWNER TO postgres;

--
-- Name: bookings_booking_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.bookings_booking_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bookings_booking_id_seq OWNER TO postgres;

--
-- Name: bookings_booking_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.bookings_booking_id_seq OWNED BY public.bookings.booking_id;


--
-- Name: grounds; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.grounds (
    ground_id integer NOT NULL,
    ground_name character varying(100) NOT NULL,
    location character varying(100) NOT NULL,
    sport_type character varying(50) NOT NULL,
    creator_id integer,
    priority integer DEFAULT 100 NOT NULL
);


ALTER TABLE public.grounds OWNER TO postgres;

--
-- Name: grounds_ground_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.grounds_ground_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.grounds_ground_id_seq OWNER TO postgres;

--
-- Name: grounds_ground_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.grounds_ground_id_seq OWNED BY public.grounds.ground_id;


--
-- Name: promotions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.promotions (
    promotion_id integer NOT NULL,
    ground_id integer,
    creator_id integer,
    status character varying(50) DEFAULT 'Pending'::character varying,
    promotion_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    details text,
    CONSTRAINT promotions_status_check CHECK (((status)::text = ANY ((ARRAY['Pending'::character varying, 'Approved'::character varying, 'Rejected'::character varying])::text[])))
);


ALTER TABLE public.promotions OWNER TO postgres;

--
-- Name: promotions_promotion_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.promotions_promotion_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.promotions_promotion_id_seq OWNER TO postgres;

--
-- Name: promotions_promotion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.promotions_promotion_id_seq OWNED BY public.promotions.promotion_id;


--
-- Name: receipts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.receipts (
    receipt_id integer NOT NULL,
    booking_id integer NOT NULL,
    user_id integer NOT NULL,
    ground_id integer NOT NULL,
    total_amount numeric(10,2) NOT NULL,
    issued_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.receipts OWNER TO postgres;

--
-- Name: receipts_receipt_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.receipts_receipt_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.receipts_receipt_id_seq OWNER TO postgres;

--
-- Name: receipts_receipt_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.receipts_receipt_id_seq OWNED BY public.receipts.receipt_id;


--
-- Name: tournaments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tournaments (
    tournament_id integer NOT NULL,
    tournament_name character varying(255) NOT NULL,
    sport_type character varying(100) NOT NULL,
    location character varying(255),
    start_date date,
    end_date date,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.tournaments OWNER TO postgres;

--
-- Name: tournaments_tournament_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.tournaments_tournament_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tournaments_tournament_id_seq OWNER TO postgres;

--
-- Name: tournaments_tournament_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.tournaments_tournament_id_seq OWNED BY public.tournaments.tournament_id;


--
-- Name: user_issues; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_issues (
    issue_id integer NOT NULL,
    user_id integer,
    issue_type character varying(255),
    description text,
    status character varying(50) DEFAULT 'Open'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_issues OWNER TO postgres;

--
-- Name: user_issues_issue_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.user_issues_issue_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.user_issues_issue_id_seq OWNER TO postgres;

--
-- Name: user_issues_issue_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.user_issues_issue_id_seq OWNED BY public.user_issues.issue_id;


--
-- Name: user_tournaments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_tournaments (
    user_id integer NOT NULL,
    tournament_id integer NOT NULL,
    joined_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.user_tournaments OWNER TO postgres;

--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    user_id integer NOT NULL,
    name character varying(100) NOT NULL,
    email character varying(255) NOT NULL,
    password character varying(255) NOT NULL,
    phone_number character varying(15),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    user_type character varying(50) DEFAULT 'regular'::character varying
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: users_user_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_user_id_seq OWNER TO postgres;

--
-- Name: users_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_user_id_seq OWNED BY public.users.user_id;


--
-- Name: wallet; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wallet (
    wallet_id integer NOT NULL,
    user_id integer,
    balance numeric(10,2) DEFAULT 0,
    CONSTRAINT wallet_balance_check CHECK ((balance >= (0)::numeric))
);


ALTER TABLE public.wallet OWNER TO postgres;

--
-- Name: wallet_transactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wallet_transactions (
    transaction_id integer NOT NULL,
    wallet_id integer,
    transaction_type character varying(50),
    amount numeric(10,2),
    transaction_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    description text,
    CONSTRAINT wallet_transactions_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT wallet_transactions_transaction_type_check CHECK (((transaction_type)::text = ANY ((ARRAY['credit'::character varying, 'debit'::character varying])::text[])))
);


ALTER TABLE public.wallet_transactions OWNER TO postgres;

--
-- Name: wallet_transactions_transaction_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wallet_transactions_transaction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wallet_transactions_transaction_id_seq OWNER TO postgres;

--
-- Name: wallet_transactions_transaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wallet_transactions_transaction_id_seq OWNED BY public.wallet_transactions.transaction_id;


--
-- Name: wallet_wallet_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wallet_wallet_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wallet_wallet_id_seq OWNER TO postgres;

--
-- Name: wallet_wallet_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wallet_wallet_id_seq OWNED BY public.wallet.wallet_id;


--
-- Name: availability availability_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.availability ALTER COLUMN availability_id SET DEFAULT nextval('public.availability_availability_id_seq'::regclass);


--
-- Name: bookings booking_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bookings ALTER COLUMN booking_id SET DEFAULT nextval('public.bookings_booking_id_seq'::regclass);


--
-- Name: grounds ground_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grounds ALTER COLUMN ground_id SET DEFAULT nextval('public.grounds_ground_id_seq'::regclass);


--
-- Name: promotions promotion_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions ALTER COLUMN promotion_id SET DEFAULT nextval('public.promotions_promotion_id_seq'::regclass);


--
-- Name: receipts receipt_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.receipts ALTER COLUMN receipt_id SET DEFAULT nextval('public.receipts_receipt_id_seq'::regclass);


--
-- Name: tournaments tournament_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tournaments ALTER COLUMN tournament_id SET DEFAULT nextval('public.tournaments_tournament_id_seq'::regclass);


--
-- Name: user_issues issue_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_issues ALTER COLUMN issue_id SET DEFAULT nextval('public.user_issues_issue_id_seq'::regclass);


--
-- Name: users user_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN user_id SET DEFAULT nextval('public.users_user_id_seq'::regclass);


--
-- Name: wallet wallet_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet ALTER COLUMN wallet_id SET DEFAULT nextval('public.wallet_wallet_id_seq'::regclass);


--
-- Name: wallet_transactions transaction_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_transactions ALTER COLUMN transaction_id SET DEFAULT nextval('public.wallet_transactions_transaction_id_seq'::regclass);


--
-- Data for Name: availability; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.availability (availability_id, ground_id, date, time_slot, is_available) FROM stdin;
1	1	2024-11-20	Early Morning	t
2	1	2024-11-20	Morning	t
3	1	2024-11-20	Noon	t
4	1	2024-11-20	Afternoon	t
5	1	2024-11-20	Evening	t
6	1	2024-11-20	Night	t
7	1	2024-11-20	Midnight	t
8	2	2024-11-20	Early Morning	t
9	2	2024-11-20	Morning	t
10	2	2024-11-20	Noon	t
11	2	2024-11-20	Afternoon	t
12	2	2024-11-20	Evening	t
13	2	2024-11-20	Night	t
14	2	2024-11-20	Midnight	t
15	3	2024-11-20	Early Morning	t
16	3	2024-11-20	Morning	t
17	3	2024-11-20	Noon	t
18	3	2024-11-20	Afternoon	t
19	3	2024-11-20	Evening	t
20	3	2024-11-20	Night	t
21	3	2024-11-20	Midnight	t
22	4	2024-11-20	Early Morning	t
23	4	2024-11-20	Morning	t
24	4	2024-11-20	Noon	t
25	4	2024-11-20	Afternoon	t
26	4	2024-11-20	Evening	t
27	4	2024-11-20	Night	t
28	4	2024-11-20	Midnight	t
29	5	2024-11-20	Early Morning	t
31	5	2024-11-20	Noon	t
32	5	2024-11-20	Afternoon	t
33	5	2024-11-20	Evening	t
34	5	2024-11-20	Night	t
35	5	2024-11-20	Midnight	t
36	6	2024-11-20	Early Morning	t
37	6	2024-11-20	Morning	t
38	6	2024-11-20	Noon	t
39	6	2024-11-20	Afternoon	t
40	6	2024-11-20	Evening	t
41	6	2024-11-20	Night	t
42	6	2024-11-20	Midnight	t
43	7	2024-11-20	Early Morning	t
44	7	2024-11-20	Morning	t
45	7	2024-11-20	Noon	t
46	7	2024-11-20	Afternoon	t
47	7	2024-11-20	Evening	t
48	7	2024-11-20	Night	t
49	7	2024-11-20	Midnight	t
50	8	2024-11-20	Early Morning	t
51	8	2024-11-20	Morning	t
52	8	2024-11-20	Noon	t
53	8	2024-11-20	Afternoon	t
54	8	2024-11-20	Evening	t
55	8	2024-11-20	Night	t
56	8	2024-11-20	Midnight	t
57	9	2024-11-20	Early Morning	t
58	9	2024-11-20	Morning	t
59	9	2024-11-20	Noon	t
60	9	2024-11-20	Afternoon	t
61	9	2024-11-20	Evening	t
62	9	2024-11-20	Night	t
63	9	2024-11-20	Midnight	t
64	10	2024-11-20	Early Morning	t
65	10	2024-11-20	Morning	t
66	10	2024-11-20	Noon	t
67	10	2024-11-20	Afternoon	t
68	10	2024-11-20	Evening	t
69	10	2024-11-20	Night	t
70	10	2024-11-20	Midnight	t
71	11	2024-11-20	Early Morning	t
72	11	2024-11-20	Morning	t
73	11	2024-11-20	Noon	t
74	11	2024-11-20	Afternoon	t
75	11	2024-11-20	Evening	t
76	11	2024-11-20	Night	t
77	11	2024-11-20	Midnight	t
78	12	2024-11-20	Early Morning	t
79	12	2024-11-20	Morning	t
80	12	2024-11-20	Noon	t
81	12	2024-11-20	Afternoon	t
82	12	2024-11-20	Evening	t
83	12	2024-11-20	Night	t
84	12	2024-11-20	Midnight	t
85	13	2024-11-20	Early Morning	t
86	13	2024-11-20	Morning	t
87	13	2024-11-20	Noon	t
88	13	2024-11-20	Afternoon	t
89	13	2024-11-20	Evening	t
90	13	2024-11-20	Night	t
91	13	2024-11-20	Midnight	t
92	14	2024-11-20	Early Morning	t
93	14	2024-11-20	Morning	t
94	14	2024-11-20	Noon	t
95	14	2024-11-20	Afternoon	t
96	14	2024-11-20	Evening	t
97	14	2024-11-20	Night	t
98	14	2024-11-20	Midnight	t
99	15	2024-11-20	Early Morning	t
100	15	2024-11-20	Morning	t
101	15	2024-11-20	Noon	t
102	15	2024-11-20	Afternoon	t
103	15	2024-11-20	Evening	t
104	15	2024-11-20	Night	t
105	15	2024-11-20	Midnight	t
106	16	2024-11-20	Early Morning	t
107	16	2024-11-20	Morning	t
108	16	2024-11-20	Noon	t
109	16	2024-11-20	Afternoon	t
110	16	2024-11-20	Evening	t
111	16	2024-11-20	Night	t
112	16	2024-11-20	Midnight	t
113	17	2024-11-20	Early Morning	t
114	17	2024-11-20	Morning	t
115	17	2024-11-20	Noon	t
116	17	2024-11-20	Afternoon	t
117	17	2024-11-20	Evening	t
118	17	2024-11-20	Night	t
119	17	2024-11-20	Midnight	t
120	18	2024-11-20	Early Morning	t
121	18	2024-11-20	Morning	t
122	18	2024-11-20	Noon	t
123	18	2024-11-20	Afternoon	t
124	18	2024-11-20	Evening	t
125	18	2024-11-20	Night	t
126	18	2024-11-20	Midnight	t
127	19	2024-11-20	Early Morning	t
128	19	2024-11-20	Morning	t
129	19	2024-11-20	Noon	t
130	19	2024-11-20	Afternoon	t
131	19	2024-11-20	Evening	t
132	19	2024-11-20	Night	t
133	19	2024-11-20	Midnight	t
134	20	2024-11-20	Early Morning	t
135	20	2024-11-20	Morning	t
136	20	2024-11-20	Noon	t
137	20	2024-11-20	Afternoon	t
138	20	2024-11-20	Evening	t
139	20	2024-11-20	Night	t
140	20	2024-11-20	Midnight	t
141	21	2024-11-20	Early Morning	t
142	21	2024-11-20	Morning	t
143	21	2024-11-20	Noon	t
144	21	2024-11-20	Afternoon	t
145	21	2024-11-20	Evening	t
146	21	2024-11-20	Night	t
147	21	2024-11-20	Midnight	t
148	22	2024-11-20	Early Morning	t
149	22	2024-11-20	Morning	t
150	22	2024-11-20	Noon	t
151	22	2024-11-20	Afternoon	t
152	22	2024-11-20	Evening	t
153	22	2024-11-20	Night	t
154	22	2024-11-20	Midnight	t
155	23	2024-11-20	Early Morning	t
156	23	2024-11-20	Morning	t
157	23	2024-11-20	Noon	t
158	23	2024-11-20	Afternoon	t
159	23	2024-11-20	Evening	t
160	23	2024-11-20	Night	t
161	23	2024-11-20	Midnight	t
162	24	2024-11-20	Early Morning	t
163	24	2024-11-20	Morning	t
164	24	2024-11-20	Noon	t
165	24	2024-11-20	Afternoon	t
166	24	2024-11-20	Evening	t
167	24	2024-11-20	Night	t
168	24	2024-11-20	Midnight	t
169	25	2024-11-20	Early Morning	t
170	25	2024-11-20	Morning	t
171	25	2024-11-20	Noon	t
172	25	2024-11-20	Afternoon	t
173	25	2024-11-20	Evening	t
174	25	2024-11-20	Night	t
175	25	2024-11-20	Midnight	t
176	26	2024-11-20	Early Morning	t
177	26	2024-11-20	Morning	t
178	26	2024-11-20	Noon	t
179	26	2024-11-20	Afternoon	t
180	26	2024-11-20	Evening	t
181	26	2024-11-20	Night	t
182	26	2024-11-20	Midnight	t
183	27	2024-11-20	Early Morning	t
184	27	2024-11-20	Morning	t
185	27	2024-11-20	Noon	t
186	27	2024-11-20	Afternoon	t
187	27	2024-11-20	Evening	t
188	27	2024-11-20	Night	t
189	27	2024-11-20	Midnight	t
190	28	2024-11-20	Early Morning	t
191	28	2024-11-20	Morning	t
192	28	2024-11-20	Noon	t
193	28	2024-11-20	Afternoon	t
194	28	2024-11-20	Evening	t
195	28	2024-11-20	Night	t
196	28	2024-11-20	Midnight	t
197	29	2024-11-20	Early Morning	t
198	29	2024-11-20	Morning	t
199	29	2024-11-20	Noon	t
200	29	2024-11-20	Afternoon	t
201	29	2024-11-20	Evening	t
202	29	2024-11-20	Night	t
203	29	2024-11-20	Midnight	t
204	30	2024-11-20	Early Morning	t
205	30	2024-11-20	Morning	t
206	30	2024-11-20	Noon	t
207	30	2024-11-20	Afternoon	t
208	30	2024-11-20	Evening	t
209	30	2024-11-20	Night	t
210	30	2024-11-20	Midnight	t
211	31	2024-11-20	Early Morning	t
212	31	2024-11-20	Morning	t
213	31	2024-11-20	Noon	t
214	31	2024-11-20	Afternoon	t
215	31	2024-11-20	Evening	t
216	31	2024-11-20	Night	t
217	31	2024-11-20	Midnight	t
218	32	2024-11-20	Early Morning	t
219	32	2024-11-20	Morning	t
220	32	2024-11-20	Noon	t
221	32	2024-11-20	Afternoon	t
222	32	2024-11-20	Evening	t
223	32	2024-11-20	Night	t
224	32	2024-11-20	Midnight	t
225	33	2024-11-20	Early Morning	t
226	33	2024-11-20	Morning	t
227	33	2024-11-20	Noon	t
228	33	2024-11-20	Afternoon	t
229	33	2024-11-20	Evening	t
230	33	2024-11-20	Night	t
231	33	2024-11-20	Midnight	t
232	34	2024-11-20	Early Morning	t
233	34	2024-11-20	Morning	t
234	34	2024-11-20	Noon	t
235	34	2024-11-20	Afternoon	t
236	34	2024-11-20	Evening	t
237	34	2024-11-20	Night	t
238	34	2024-11-20	Midnight	t
239	35	2024-11-20	Early Morning	t
240	35	2024-11-20	Morning	t
241	35	2024-11-20	Noon	t
242	35	2024-11-20	Afternoon	t
243	35	2024-11-20	Evening	t
244	35	2024-11-20	Night	t
245	35	2024-11-20	Midnight	t
246	36	2024-11-20	Early Morning	t
247	36	2024-11-20	Morning	t
248	36	2024-11-20	Noon	t
249	36	2024-11-20	Afternoon	t
250	36	2024-11-20	Evening	t
251	36	2024-11-20	Night	t
252	36	2024-11-20	Midnight	t
253	37	2024-11-20	Early Morning	t
254	37	2024-11-20	Morning	t
255	37	2024-11-20	Noon	t
256	37	2024-11-20	Afternoon	t
257	37	2024-11-20	Evening	t
258	37	2024-11-20	Night	t
259	37	2024-11-20	Midnight	t
260	38	2024-11-20	Early Morning	t
261	38	2024-11-20	Morning	t
262	38	2024-11-20	Noon	t
263	38	2024-11-20	Afternoon	t
264	38	2024-11-20	Evening	t
265	38	2024-11-20	Night	t
266	38	2024-11-20	Midnight	t
267	39	2024-11-20	Early Morning	t
268	39	2024-11-20	Morning	t
269	39	2024-11-20	Noon	t
270	39	2024-11-20	Afternoon	t
271	39	2024-11-20	Evening	t
272	39	2024-11-20	Night	t
273	39	2024-11-20	Midnight	t
274	40	2024-11-20	Early Morning	t
275	40	2024-11-20	Morning	t
276	40	2024-11-20	Noon	t
277	40	2024-11-20	Afternoon	t
278	40	2024-11-20	Evening	t
279	40	2024-11-20	Night	t
280	40	2024-11-20	Midnight	t
281	41	2024-11-20	Early Morning	t
282	41	2024-11-20	Morning	t
283	41	2024-11-20	Noon	t
284	41	2024-11-20	Afternoon	t
285	41	2024-11-20	Evening	t
286	41	2024-11-20	Night	t
287	41	2024-11-20	Midnight	t
288	1	2024-11-21	Early Morning	t
289	1	2024-11-21	Morning	t
290	1	2024-11-21	Noon	t
292	1	2024-11-21	Evening	t
294	1	2024-11-21	Midnight	t
295	2	2024-11-21	Early Morning	t
296	2	2024-11-21	Morning	t
297	2	2024-11-21	Noon	t
298	2	2024-11-21	Afternoon	t
299	2	2024-11-21	Evening	t
300	2	2024-11-21	Night	t
301	2	2024-11-21	Midnight	t
302	3	2024-11-21	Early Morning	t
303	3	2024-11-21	Morning	t
304	3	2024-11-21	Noon	t
305	3	2024-11-21	Afternoon	t
306	3	2024-11-21	Evening	t
293	1	2024-11-21	Night	f
307	3	2024-11-21	Night	t
308	3	2024-11-21	Midnight	t
309	4	2024-11-21	Early Morning	t
310	4	2024-11-21	Morning	t
311	4	2024-11-21	Noon	t
312	4	2024-11-21	Afternoon	t
313	4	2024-11-21	Evening	t
314	4	2024-11-21	Night	t
315	4	2024-11-21	Midnight	t
316	5	2024-11-21	Early Morning	t
317	5	2024-11-21	Morning	t
318	5	2024-11-21	Noon	t
319	5	2024-11-21	Afternoon	t
320	5	2024-11-21	Evening	t
321	5	2024-11-21	Night	t
322	5	2024-11-21	Midnight	t
323	6	2024-11-21	Early Morning	t
324	6	2024-11-21	Morning	t
325	6	2024-11-21	Noon	t
326	6	2024-11-21	Afternoon	t
327	6	2024-11-21	Evening	t
328	6	2024-11-21	Night	t
329	6	2024-11-21	Midnight	t
331	7	2024-11-21	Morning	t
332	7	2024-11-21	Noon	t
333	7	2024-11-21	Afternoon	t
334	7	2024-11-21	Evening	t
335	7	2024-11-21	Night	t
336	7	2024-11-21	Midnight	t
337	8	2024-11-21	Early Morning	t
338	8	2024-11-21	Morning	t
339	8	2024-11-21	Noon	t
340	8	2024-11-21	Afternoon	t
341	8	2024-11-21	Evening	t
342	8	2024-11-21	Night	t
343	8	2024-11-21	Midnight	t
344	9	2024-11-21	Early Morning	t
345	9	2024-11-21	Morning	t
346	9	2024-11-21	Noon	t
347	9	2024-11-21	Afternoon	t
348	9	2024-11-21	Evening	t
349	9	2024-11-21	Night	t
350	9	2024-11-21	Midnight	t
351	10	2024-11-21	Early Morning	t
352	10	2024-11-21	Morning	t
353	10	2024-11-21	Noon	t
355	10	2024-11-21	Evening	t
357	10	2024-11-21	Midnight	t
358	11	2024-11-21	Early Morning	t
359	11	2024-11-21	Morning	t
360	11	2024-11-21	Noon	t
361	11	2024-11-21	Afternoon	t
362	11	2024-11-21	Evening	t
363	11	2024-11-21	Night	t
364	11	2024-11-21	Midnight	t
365	12	2024-11-21	Early Morning	t
366	12	2024-11-21	Morning	t
367	12	2024-11-21	Noon	t
368	12	2024-11-21	Afternoon	t
369	12	2024-11-21	Evening	t
370	12	2024-11-21	Night	t
371	12	2024-11-21	Midnight	t
373	13	2024-11-21	Morning	t
374	13	2024-11-21	Noon	t
375	13	2024-11-21	Afternoon	t
377	13	2024-11-21	Night	t
379	14	2024-11-21	Early Morning	t
380	14	2024-11-21	Morning	t
381	14	2024-11-21	Noon	t
382	14	2024-11-21	Afternoon	t
383	14	2024-11-21	Evening	t
384	14	2024-11-21	Night	t
385	14	2024-11-21	Midnight	t
386	15	2024-11-21	Early Morning	t
387	15	2024-11-21	Morning	t
388	15	2024-11-21	Noon	t
389	15	2024-11-21	Afternoon	t
390	15	2024-11-21	Evening	t
391	15	2024-11-21	Night	t
392	15	2024-11-21	Midnight	t
393	16	2024-11-21	Early Morning	t
394	16	2024-11-21	Morning	t
395	16	2024-11-21	Noon	t
396	16	2024-11-21	Afternoon	t
397	16	2024-11-21	Evening	t
398	16	2024-11-21	Night	t
399	16	2024-11-21	Midnight	t
400	17	2024-11-21	Early Morning	t
401	17	2024-11-21	Morning	t
402	17	2024-11-21	Noon	t
403	17	2024-11-21	Afternoon	t
404	17	2024-11-21	Evening	t
405	17	2024-11-21	Night	t
406	17	2024-11-21	Midnight	t
407	18	2024-11-21	Early Morning	t
408	18	2024-11-21	Morning	t
409	18	2024-11-21	Noon	t
410	18	2024-11-21	Afternoon	t
411	18	2024-11-21	Evening	t
412	18	2024-11-21	Night	t
413	18	2024-11-21	Midnight	t
414	19	2024-11-21	Early Morning	t
415	19	2024-11-21	Morning	t
416	19	2024-11-21	Noon	t
417	19	2024-11-21	Afternoon	t
418	19	2024-11-21	Evening	t
419	19	2024-11-21	Night	t
420	19	2024-11-21	Midnight	t
421	20	2024-11-21	Early Morning	t
422	20	2024-11-21	Morning	t
423	20	2024-11-21	Noon	t
424	20	2024-11-21	Afternoon	t
425	20	2024-11-21	Evening	t
426	20	2024-11-21	Night	t
427	20	2024-11-21	Midnight	t
428	21	2024-11-21	Early Morning	t
429	21	2024-11-21	Morning	t
430	21	2024-11-21	Noon	t
431	21	2024-11-21	Afternoon	t
432	21	2024-11-21	Evening	t
433	21	2024-11-21	Night	t
434	21	2024-11-21	Midnight	t
435	22	2024-11-21	Early Morning	t
436	22	2024-11-21	Morning	t
437	22	2024-11-21	Noon	t
438	22	2024-11-21	Afternoon	t
439	22	2024-11-21	Evening	t
440	22	2024-11-21	Night	t
441	22	2024-11-21	Midnight	t
442	23	2024-11-21	Early Morning	t
443	23	2024-11-21	Morning	t
444	23	2024-11-21	Noon	t
445	23	2024-11-21	Afternoon	t
446	23	2024-11-21	Evening	t
447	23	2024-11-21	Night	t
448	23	2024-11-21	Midnight	t
449	24	2024-11-21	Early Morning	t
450	24	2024-11-21	Morning	t
451	24	2024-11-21	Noon	t
452	24	2024-11-21	Afternoon	t
453	24	2024-11-21	Evening	t
454	24	2024-11-21	Night	t
455	24	2024-11-21	Midnight	t
456	25	2024-11-21	Early Morning	t
457	25	2024-11-21	Morning	t
458	25	2024-11-21	Noon	t
459	25	2024-11-21	Afternoon	t
372	13	2024-11-21	Early Morning	f
378	13	2024-11-21	Midnight	f
376	13	2024-11-21	Evening	f
354	10	2024-11-21	Afternoon	f
356	10	2024-11-21	Night	f
460	25	2024-11-21	Evening	t
461	25	2024-11-21	Night	t
462	25	2024-11-21	Midnight	t
463	26	2024-11-21	Early Morning	t
464	26	2024-11-21	Morning	t
465	26	2024-11-21	Noon	t
466	26	2024-11-21	Afternoon	t
467	26	2024-11-21	Evening	t
468	26	2024-11-21	Night	t
469	26	2024-11-21	Midnight	t
470	27	2024-11-21	Early Morning	t
471	27	2024-11-21	Morning	t
472	27	2024-11-21	Noon	t
473	27	2024-11-21	Afternoon	t
475	27	2024-11-21	Night	t
476	27	2024-11-21	Midnight	t
477	28	2024-11-21	Early Morning	t
478	28	2024-11-21	Morning	t
479	28	2024-11-21	Noon	t
480	28	2024-11-21	Afternoon	t
481	28	2024-11-21	Evening	t
482	28	2024-11-21	Night	t
484	29	2024-11-21	Early Morning	t
485	29	2024-11-21	Morning	t
486	29	2024-11-21	Noon	t
487	29	2024-11-21	Afternoon	t
488	29	2024-11-21	Evening	t
489	29	2024-11-21	Night	t
490	29	2024-11-21	Midnight	t
491	30	2024-11-21	Early Morning	t
492	30	2024-11-21	Morning	t
493	30	2024-11-21	Noon	t
494	30	2024-11-21	Afternoon	t
495	30	2024-11-21	Evening	t
496	30	2024-11-21	Night	t
497	30	2024-11-21	Midnight	t
499	31	2024-11-21	Morning	t
500	31	2024-11-21	Noon	t
501	31	2024-11-21	Afternoon	t
502	31	2024-11-21	Evening	t
503	31	2024-11-21	Night	t
504	31	2024-11-21	Midnight	t
505	32	2024-11-21	Early Morning	t
506	32	2024-11-21	Morning	t
507	32	2024-11-21	Noon	t
508	32	2024-11-21	Afternoon	t
509	32	2024-11-21	Evening	t
510	32	2024-11-21	Night	t
511	32	2024-11-21	Midnight	t
512	33	2024-11-21	Early Morning	t
513	33	2024-11-21	Morning	t
514	33	2024-11-21	Noon	t
515	33	2024-11-21	Afternoon	t
516	33	2024-11-21	Evening	t
517	33	2024-11-21	Night	t
518	33	2024-11-21	Midnight	t
519	34	2024-11-21	Early Morning	t
520	34	2024-11-21	Morning	t
521	34	2024-11-21	Noon	t
522	34	2024-11-21	Afternoon	t
523	34	2024-11-21	Evening	t
524	34	2024-11-21	Night	t
525	34	2024-11-21	Midnight	t
526	35	2024-11-21	Early Morning	t
527	35	2024-11-21	Morning	t
528	35	2024-11-21	Noon	t
529	35	2024-11-21	Afternoon	t
530	35	2024-11-21	Evening	t
531	35	2024-11-21	Night	t
532	35	2024-11-21	Midnight	t
533	36	2024-11-21	Early Morning	t
534	36	2024-11-21	Morning	t
535	36	2024-11-21	Noon	t
536	36	2024-11-21	Afternoon	t
537	36	2024-11-21	Evening	t
538	36	2024-11-21	Night	t
539	36	2024-11-21	Midnight	t
540	37	2024-11-21	Early Morning	t
541	37	2024-11-21	Morning	t
542	37	2024-11-21	Noon	t
543	37	2024-11-21	Afternoon	t
544	37	2024-11-21	Evening	t
545	37	2024-11-21	Night	t
546	37	2024-11-21	Midnight	t
547	38	2024-11-21	Early Morning	t
548	38	2024-11-21	Morning	t
549	38	2024-11-21	Noon	t
550	38	2024-11-21	Afternoon	t
551	38	2024-11-21	Evening	t
552	38	2024-11-21	Night	t
553	38	2024-11-21	Midnight	t
554	39	2024-11-21	Early Morning	t
555	39	2024-11-21	Morning	t
556	39	2024-11-21	Noon	t
557	39	2024-11-21	Afternoon	t
558	39	2024-11-21	Evening	t
559	39	2024-11-21	Night	t
560	39	2024-11-21	Midnight	t
561	40	2024-11-21	Early Morning	t
562	40	2024-11-21	Morning	t
563	40	2024-11-21	Noon	t
564	40	2024-11-21	Afternoon	t
565	40	2024-11-21	Evening	t
566	40	2024-11-21	Night	t
567	40	2024-11-21	Midnight	t
568	41	2024-11-21	Early Morning	t
569	41	2024-11-21	Morning	t
570	41	2024-11-21	Noon	t
571	41	2024-11-21	Afternoon	t
572	41	2024-11-21	Evening	t
573	41	2024-11-21	Night	t
574	41	2024-11-21	Midnight	t
575	1	2024-11-22	Early Morning	t
576	1	2024-11-22	Morning	t
577	1	2024-11-22	Noon	t
578	1	2024-11-22	Afternoon	t
579	1	2024-11-22	Evening	t
580	1	2024-11-22	Night	t
581	1	2024-11-22	Midnight	t
582	2	2024-11-22	Early Morning	t
583	2	2024-11-22	Morning	t
584	2	2024-11-22	Noon	t
585	2	2024-11-22	Afternoon	t
586	2	2024-11-22	Evening	t
587	2	2024-11-22	Night	t
588	2	2024-11-22	Midnight	t
589	3	2024-11-22	Early Morning	t
590	3	2024-11-22	Morning	t
591	3	2024-11-22	Noon	t
592	3	2024-11-22	Afternoon	t
593	3	2024-11-22	Evening	t
594	3	2024-11-22	Night	t
595	3	2024-11-22	Midnight	t
596	4	2024-11-22	Early Morning	t
597	4	2024-11-22	Morning	t
598	4	2024-11-22	Noon	t
599	4	2024-11-22	Afternoon	t
600	4	2024-11-22	Evening	t
601	4	2024-11-22	Night	t
602	4	2024-11-22	Midnight	t
603	5	2024-11-22	Early Morning	t
604	5	2024-11-22	Morning	t
605	5	2024-11-22	Noon	t
606	5	2024-11-22	Afternoon	t
607	5	2024-11-22	Evening	t
608	5	2024-11-22	Night	t
609	5	2024-11-22	Midnight	t
610	6	2024-11-22	Early Morning	t
611	6	2024-11-22	Morning	t
612	6	2024-11-22	Noon	t
474	27	2024-11-21	Evening	f
483	28	2024-11-21	Midnight	f
613	6	2024-11-22	Afternoon	t
614	6	2024-11-22	Evening	t
615	6	2024-11-22	Night	t
616	6	2024-11-22	Midnight	t
617	7	2024-11-22	Early Morning	t
618	7	2024-11-22	Morning	t
619	7	2024-11-22	Noon	t
620	7	2024-11-22	Afternoon	t
621	7	2024-11-22	Evening	t
622	7	2024-11-22	Night	t
623	7	2024-11-22	Midnight	t
624	8	2024-11-22	Early Morning	t
625	8	2024-11-22	Morning	t
626	8	2024-11-22	Noon	t
627	8	2024-11-22	Afternoon	t
628	8	2024-11-22	Evening	t
629	8	2024-11-22	Night	t
630	8	2024-11-22	Midnight	t
631	9	2024-11-22	Early Morning	t
632	9	2024-11-22	Morning	t
633	9	2024-11-22	Noon	t
634	9	2024-11-22	Afternoon	t
635	9	2024-11-22	Evening	t
636	9	2024-11-22	Night	t
637	9	2024-11-22	Midnight	t
638	10	2024-11-22	Early Morning	t
639	10	2024-11-22	Morning	t
640	10	2024-11-22	Noon	t
641	10	2024-11-22	Afternoon	t
642	10	2024-11-22	Evening	t
643	10	2024-11-22	Night	t
644	10	2024-11-22	Midnight	t
645	11	2024-11-22	Early Morning	t
646	11	2024-11-22	Morning	t
647	11	2024-11-22	Noon	t
648	11	2024-11-22	Afternoon	t
649	11	2024-11-22	Evening	t
650	11	2024-11-22	Night	t
651	11	2024-11-22	Midnight	t
652	12	2024-11-22	Early Morning	t
653	12	2024-11-22	Morning	t
654	12	2024-11-22	Noon	t
655	12	2024-11-22	Afternoon	t
656	12	2024-11-22	Evening	t
657	12	2024-11-22	Night	t
658	12	2024-11-22	Midnight	t
659	13	2024-11-22	Early Morning	t
660	13	2024-11-22	Morning	t
661	13	2024-11-22	Noon	t
662	13	2024-11-22	Afternoon	t
663	13	2024-11-22	Evening	t
664	13	2024-11-22	Night	t
665	13	2024-11-22	Midnight	t
666	14	2024-11-22	Early Morning	t
667	14	2024-11-22	Morning	t
668	14	2024-11-22	Noon	t
669	14	2024-11-22	Afternoon	t
670	14	2024-11-22	Evening	t
671	14	2024-11-22	Night	t
672	14	2024-11-22	Midnight	t
673	15	2024-11-22	Early Morning	t
674	15	2024-11-22	Morning	t
675	15	2024-11-22	Noon	t
676	15	2024-11-22	Afternoon	t
677	15	2024-11-22	Evening	t
678	15	2024-11-22	Night	t
679	15	2024-11-22	Midnight	t
680	16	2024-11-22	Early Morning	t
681	16	2024-11-22	Morning	t
682	16	2024-11-22	Noon	t
683	16	2024-11-22	Afternoon	t
684	16	2024-11-22	Evening	t
685	16	2024-11-22	Night	t
686	16	2024-11-22	Midnight	t
687	17	2024-11-22	Early Morning	t
688	17	2024-11-22	Morning	t
689	17	2024-11-22	Noon	t
690	17	2024-11-22	Afternoon	t
691	17	2024-11-22	Evening	t
692	17	2024-11-22	Night	t
693	17	2024-11-22	Midnight	t
694	18	2024-11-22	Early Morning	t
695	18	2024-11-22	Morning	t
696	18	2024-11-22	Noon	t
697	18	2024-11-22	Afternoon	t
698	18	2024-11-22	Evening	t
699	18	2024-11-22	Night	t
700	18	2024-11-22	Midnight	t
701	19	2024-11-22	Early Morning	t
702	19	2024-11-22	Morning	t
703	19	2024-11-22	Noon	t
704	19	2024-11-22	Afternoon	t
705	19	2024-11-22	Evening	t
706	19	2024-11-22	Night	t
707	19	2024-11-22	Midnight	t
708	20	2024-11-22	Early Morning	t
709	20	2024-11-22	Morning	t
710	20	2024-11-22	Noon	t
711	20	2024-11-22	Afternoon	t
712	20	2024-11-22	Evening	t
713	20	2024-11-22	Night	t
714	20	2024-11-22	Midnight	t
715	21	2024-11-22	Early Morning	t
716	21	2024-11-22	Morning	t
717	21	2024-11-22	Noon	t
718	21	2024-11-22	Afternoon	t
719	21	2024-11-22	Evening	t
720	21	2024-11-22	Night	t
721	21	2024-11-22	Midnight	t
722	22	2024-11-22	Early Morning	t
723	22	2024-11-22	Morning	t
724	22	2024-11-22	Noon	t
725	22	2024-11-22	Afternoon	t
726	22	2024-11-22	Evening	t
727	22	2024-11-22	Night	t
728	22	2024-11-22	Midnight	t
729	23	2024-11-22	Early Morning	t
730	23	2024-11-22	Morning	t
731	23	2024-11-22	Noon	t
732	23	2024-11-22	Afternoon	t
733	23	2024-11-22	Evening	t
734	23	2024-11-22	Night	t
735	23	2024-11-22	Midnight	t
736	24	2024-11-22	Early Morning	t
737	24	2024-11-22	Morning	t
738	24	2024-11-22	Noon	t
739	24	2024-11-22	Afternoon	t
740	24	2024-11-22	Evening	t
741	24	2024-11-22	Night	t
742	24	2024-11-22	Midnight	t
743	25	2024-11-22	Early Morning	t
744	25	2024-11-22	Morning	t
745	25	2024-11-22	Noon	t
746	25	2024-11-22	Afternoon	t
747	25	2024-11-22	Evening	t
748	25	2024-11-22	Night	t
749	25	2024-11-22	Midnight	t
750	26	2024-11-22	Early Morning	t
751	26	2024-11-22	Morning	t
752	26	2024-11-22	Noon	t
753	26	2024-11-22	Afternoon	t
754	26	2024-11-22	Evening	t
755	26	2024-11-22	Night	t
756	26	2024-11-22	Midnight	t
757	27	2024-11-22	Early Morning	t
758	27	2024-11-22	Morning	t
759	27	2024-11-22	Noon	t
760	27	2024-11-22	Afternoon	t
761	27	2024-11-22	Evening	t
762	27	2024-11-22	Night	t
763	27	2024-11-22	Midnight	t
764	28	2024-11-22	Early Morning	t
765	28	2024-11-22	Morning	t
766	28	2024-11-22	Noon	t
767	28	2024-11-22	Afternoon	t
768	28	2024-11-22	Evening	t
769	28	2024-11-22	Night	t
770	28	2024-11-22	Midnight	t
771	29	2024-11-22	Early Morning	t
772	29	2024-11-22	Morning	t
773	29	2024-11-22	Noon	t
774	29	2024-11-22	Afternoon	t
775	29	2024-11-22	Evening	t
776	29	2024-11-22	Night	t
777	29	2024-11-22	Midnight	t
778	30	2024-11-22	Early Morning	t
779	30	2024-11-22	Morning	t
780	30	2024-11-22	Noon	t
781	30	2024-11-22	Afternoon	t
782	30	2024-11-22	Evening	t
783	30	2024-11-22	Night	t
784	30	2024-11-22	Midnight	t
785	31	2024-11-22	Early Morning	t
786	31	2024-11-22	Morning	t
787	31	2024-11-22	Noon	t
788	31	2024-11-22	Afternoon	t
789	31	2024-11-22	Evening	t
790	31	2024-11-22	Night	t
791	31	2024-11-22	Midnight	t
792	32	2024-11-22	Early Morning	t
793	32	2024-11-22	Morning	t
794	32	2024-11-22	Noon	t
795	32	2024-11-22	Afternoon	t
796	32	2024-11-22	Evening	t
797	32	2024-11-22	Night	t
798	32	2024-11-22	Midnight	t
799	33	2024-11-22	Early Morning	t
800	33	2024-11-22	Morning	t
801	33	2024-11-22	Noon	t
802	33	2024-11-22	Afternoon	t
803	33	2024-11-22	Evening	t
804	33	2024-11-22	Night	t
805	33	2024-11-22	Midnight	t
806	34	2024-11-22	Early Morning	t
807	34	2024-11-22	Morning	t
808	34	2024-11-22	Noon	t
809	34	2024-11-22	Afternoon	t
810	34	2024-11-22	Evening	t
811	34	2024-11-22	Night	t
812	34	2024-11-22	Midnight	t
813	35	2024-11-22	Early Morning	t
814	35	2024-11-22	Morning	t
815	35	2024-11-22	Noon	t
816	35	2024-11-22	Afternoon	t
817	35	2024-11-22	Evening	t
818	35	2024-11-22	Night	t
819	35	2024-11-22	Midnight	t
820	36	2024-11-22	Early Morning	t
821	36	2024-11-22	Morning	t
822	36	2024-11-22	Noon	t
823	36	2024-11-22	Afternoon	t
824	36	2024-11-22	Evening	t
825	36	2024-11-22	Night	t
826	36	2024-11-22	Midnight	t
827	37	2024-11-22	Early Morning	t
828	37	2024-11-22	Morning	t
829	37	2024-11-22	Noon	t
830	37	2024-11-22	Afternoon	t
831	37	2024-11-22	Evening	t
832	37	2024-11-22	Night	t
833	37	2024-11-22	Midnight	t
834	38	2024-11-22	Early Morning	t
835	38	2024-11-22	Morning	t
836	38	2024-11-22	Noon	t
837	38	2024-11-22	Afternoon	t
838	38	2024-11-22	Evening	t
839	38	2024-11-22	Night	t
840	38	2024-11-22	Midnight	t
841	39	2024-11-22	Early Morning	t
842	39	2024-11-22	Morning	t
843	39	2024-11-22	Noon	t
844	39	2024-11-22	Afternoon	t
845	39	2024-11-22	Evening	t
846	39	2024-11-22	Night	t
847	39	2024-11-22	Midnight	t
848	40	2024-11-22	Early Morning	t
849	40	2024-11-22	Morning	t
850	40	2024-11-22	Noon	t
851	40	2024-11-22	Afternoon	t
852	40	2024-11-22	Evening	t
853	40	2024-11-22	Night	t
854	40	2024-11-22	Midnight	t
855	41	2024-11-22	Early Morning	t
856	41	2024-11-22	Morning	t
857	41	2024-11-22	Noon	t
858	41	2024-11-22	Afternoon	t
859	41	2024-11-22	Evening	t
860	41	2024-11-22	Night	t
861	41	2024-11-22	Midnight	t
862	1	2024-11-23	Early Morning	t
863	1	2024-11-23	Morning	t
864	1	2024-11-23	Noon	t
865	1	2024-11-23	Afternoon	t
866	1	2024-11-23	Evening	t
867	1	2024-11-23	Night	t
868	1	2024-11-23	Midnight	t
869	2	2024-11-23	Early Morning	t
870	2	2024-11-23	Morning	t
871	2	2024-11-23	Noon	t
872	2	2024-11-23	Afternoon	t
873	2	2024-11-23	Evening	t
874	2	2024-11-23	Night	t
875	2	2024-11-23	Midnight	t
876	3	2024-11-23	Early Morning	t
877	3	2024-11-23	Morning	t
878	3	2024-11-23	Noon	t
879	3	2024-11-23	Afternoon	t
880	3	2024-11-23	Evening	t
881	3	2024-11-23	Night	t
882	3	2024-11-23	Midnight	t
883	4	2024-11-23	Early Morning	t
884	4	2024-11-23	Morning	t
885	4	2024-11-23	Noon	t
886	4	2024-11-23	Afternoon	t
887	4	2024-11-23	Evening	t
888	4	2024-11-23	Night	t
889	4	2024-11-23	Midnight	t
890	5	2024-11-23	Early Morning	t
891	5	2024-11-23	Morning	t
892	5	2024-11-23	Noon	t
893	5	2024-11-23	Afternoon	t
894	5	2024-11-23	Evening	t
895	5	2024-11-23	Night	t
896	5	2024-11-23	Midnight	t
897	6	2024-11-23	Early Morning	t
898	6	2024-11-23	Morning	t
899	6	2024-11-23	Noon	t
900	6	2024-11-23	Afternoon	t
901	6	2024-11-23	Evening	t
902	6	2024-11-23	Night	t
903	6	2024-11-23	Midnight	t
904	7	2024-11-23	Early Morning	t
905	7	2024-11-23	Morning	t
906	7	2024-11-23	Noon	t
907	7	2024-11-23	Afternoon	t
908	7	2024-11-23	Evening	t
909	7	2024-11-23	Night	t
910	7	2024-11-23	Midnight	t
911	8	2024-11-23	Early Morning	t
912	8	2024-11-23	Morning	t
913	8	2024-11-23	Noon	t
914	8	2024-11-23	Afternoon	t
915	8	2024-11-23	Evening	t
916	8	2024-11-23	Night	t
917	8	2024-11-23	Midnight	t
918	9	2024-11-23	Early Morning	t
919	9	2024-11-23	Morning	t
920	9	2024-11-23	Noon	t
921	9	2024-11-23	Afternoon	t
922	9	2024-11-23	Evening	t
923	9	2024-11-23	Night	t
924	9	2024-11-23	Midnight	t
925	10	2024-11-23	Early Morning	t
926	10	2024-11-23	Morning	t
927	10	2024-11-23	Noon	t
928	10	2024-11-23	Afternoon	t
929	10	2024-11-23	Evening	t
930	10	2024-11-23	Night	t
931	10	2024-11-23	Midnight	t
932	11	2024-11-23	Early Morning	t
933	11	2024-11-23	Morning	t
934	11	2024-11-23	Noon	t
935	11	2024-11-23	Afternoon	t
936	11	2024-11-23	Evening	t
937	11	2024-11-23	Night	t
938	11	2024-11-23	Midnight	t
939	12	2024-11-23	Early Morning	t
940	12	2024-11-23	Morning	t
941	12	2024-11-23	Noon	t
942	12	2024-11-23	Afternoon	t
943	12	2024-11-23	Evening	t
944	12	2024-11-23	Night	t
945	12	2024-11-23	Midnight	t
946	13	2024-11-23	Early Morning	t
947	13	2024-11-23	Morning	t
948	13	2024-11-23	Noon	t
949	13	2024-11-23	Afternoon	t
950	13	2024-11-23	Evening	t
951	13	2024-11-23	Night	t
952	13	2024-11-23	Midnight	t
953	14	2024-11-23	Early Morning	t
954	14	2024-11-23	Morning	t
955	14	2024-11-23	Noon	t
956	14	2024-11-23	Afternoon	t
957	14	2024-11-23	Evening	t
958	14	2024-11-23	Night	t
959	14	2024-11-23	Midnight	t
960	15	2024-11-23	Early Morning	t
961	15	2024-11-23	Morning	t
962	15	2024-11-23	Noon	t
963	15	2024-11-23	Afternoon	t
964	15	2024-11-23	Evening	t
965	15	2024-11-23	Night	t
966	15	2024-11-23	Midnight	t
967	16	2024-11-23	Early Morning	t
968	16	2024-11-23	Morning	t
969	16	2024-11-23	Noon	t
970	16	2024-11-23	Afternoon	t
971	16	2024-11-23	Evening	t
972	16	2024-11-23	Night	t
973	16	2024-11-23	Midnight	t
974	17	2024-11-23	Early Morning	t
975	17	2024-11-23	Morning	t
976	17	2024-11-23	Noon	t
977	17	2024-11-23	Afternoon	t
978	17	2024-11-23	Evening	t
979	17	2024-11-23	Night	t
980	17	2024-11-23	Midnight	t
981	18	2024-11-23	Early Morning	t
982	18	2024-11-23	Morning	t
983	18	2024-11-23	Noon	t
984	18	2024-11-23	Afternoon	t
985	18	2024-11-23	Evening	t
986	18	2024-11-23	Night	t
987	18	2024-11-23	Midnight	t
988	19	2024-11-23	Early Morning	t
989	19	2024-11-23	Morning	t
990	19	2024-11-23	Noon	t
991	19	2024-11-23	Afternoon	t
992	19	2024-11-23	Evening	t
993	19	2024-11-23	Night	t
994	19	2024-11-23	Midnight	t
995	20	2024-11-23	Early Morning	t
996	20	2024-11-23	Morning	t
997	20	2024-11-23	Noon	t
998	20	2024-11-23	Afternoon	t
999	20	2024-11-23	Evening	t
1000	20	2024-11-23	Night	t
1001	20	2024-11-23	Midnight	t
1002	21	2024-11-23	Early Morning	t
1003	21	2024-11-23	Morning	t
1004	21	2024-11-23	Noon	t
1005	21	2024-11-23	Afternoon	t
1006	21	2024-11-23	Evening	t
1007	21	2024-11-23	Night	t
1008	21	2024-11-23	Midnight	t
1009	22	2024-11-23	Early Morning	t
1010	22	2024-11-23	Morning	t
1011	22	2024-11-23	Noon	t
1012	22	2024-11-23	Afternoon	t
1013	22	2024-11-23	Evening	t
1014	22	2024-11-23	Night	t
1015	22	2024-11-23	Midnight	t
1016	23	2024-11-23	Early Morning	t
1017	23	2024-11-23	Morning	t
1018	23	2024-11-23	Noon	t
1019	23	2024-11-23	Afternoon	t
1020	23	2024-11-23	Evening	t
1021	23	2024-11-23	Night	t
1022	23	2024-11-23	Midnight	t
1023	24	2024-11-23	Early Morning	t
1024	24	2024-11-23	Morning	t
1025	24	2024-11-23	Noon	t
1026	24	2024-11-23	Afternoon	t
1027	24	2024-11-23	Evening	t
1028	24	2024-11-23	Night	t
1029	24	2024-11-23	Midnight	t
1030	25	2024-11-23	Early Morning	t
1031	25	2024-11-23	Morning	t
1032	25	2024-11-23	Noon	t
1033	25	2024-11-23	Afternoon	t
1034	25	2024-11-23	Evening	t
1035	25	2024-11-23	Night	t
1036	25	2024-11-23	Midnight	t
1037	26	2024-11-23	Early Morning	t
1038	26	2024-11-23	Morning	t
1039	26	2024-11-23	Noon	t
1040	26	2024-11-23	Afternoon	t
1041	26	2024-11-23	Evening	t
1042	26	2024-11-23	Night	t
1043	26	2024-11-23	Midnight	t
1044	27	2024-11-23	Early Morning	t
1045	27	2024-11-23	Morning	t
1046	27	2024-11-23	Noon	t
1047	27	2024-11-23	Afternoon	t
1048	27	2024-11-23	Evening	t
1049	27	2024-11-23	Night	t
1050	27	2024-11-23	Midnight	t
1051	28	2024-11-23	Early Morning	t
1052	28	2024-11-23	Morning	t
1053	28	2024-11-23	Noon	t
1054	28	2024-11-23	Afternoon	t
1055	28	2024-11-23	Evening	t
1056	28	2024-11-23	Night	t
1057	28	2024-11-23	Midnight	t
1058	29	2024-11-23	Early Morning	t
1059	29	2024-11-23	Morning	t
1060	29	2024-11-23	Noon	t
1061	29	2024-11-23	Afternoon	t
1062	29	2024-11-23	Evening	t
1063	29	2024-11-23	Night	t
1064	29	2024-11-23	Midnight	t
1065	30	2024-11-23	Early Morning	t
1066	30	2024-11-23	Morning	t
1067	30	2024-11-23	Noon	t
1068	30	2024-11-23	Afternoon	t
1069	30	2024-11-23	Evening	t
1070	30	2024-11-23	Night	t
1071	30	2024-11-23	Midnight	t
1072	31	2024-11-23	Early Morning	t
1073	31	2024-11-23	Morning	t
1074	31	2024-11-23	Noon	t
1075	31	2024-11-23	Afternoon	t
1076	31	2024-11-23	Evening	t
1077	31	2024-11-23	Night	t
1078	31	2024-11-23	Midnight	t
1079	32	2024-11-23	Early Morning	t
1080	32	2024-11-23	Morning	t
1081	32	2024-11-23	Noon	t
1082	32	2024-11-23	Afternoon	t
1083	32	2024-11-23	Evening	t
1084	32	2024-11-23	Night	t
1085	32	2024-11-23	Midnight	t
1086	33	2024-11-23	Early Morning	t
1087	33	2024-11-23	Morning	t
1088	33	2024-11-23	Noon	t
1089	33	2024-11-23	Afternoon	t
1090	33	2024-11-23	Evening	t
1091	33	2024-11-23	Night	t
1092	33	2024-11-23	Midnight	t
1093	34	2024-11-23	Early Morning	t
1094	34	2024-11-23	Morning	t
1095	34	2024-11-23	Noon	t
1096	34	2024-11-23	Afternoon	t
1097	34	2024-11-23	Evening	t
1098	34	2024-11-23	Night	t
1099	34	2024-11-23	Midnight	t
1100	35	2024-11-23	Early Morning	t
1101	35	2024-11-23	Morning	t
1102	35	2024-11-23	Noon	t
1103	35	2024-11-23	Afternoon	t
1104	35	2024-11-23	Evening	t
1105	35	2024-11-23	Night	t
1106	35	2024-11-23	Midnight	t
1107	36	2024-11-23	Early Morning	t
1108	36	2024-11-23	Morning	t
1109	36	2024-11-23	Noon	t
1110	36	2024-11-23	Afternoon	t
1111	36	2024-11-23	Evening	t
1112	36	2024-11-23	Night	t
1113	36	2024-11-23	Midnight	t
1114	37	2024-11-23	Early Morning	t
1115	37	2024-11-23	Morning	t
1116	37	2024-11-23	Noon	t
1117	37	2024-11-23	Afternoon	t
1118	37	2024-11-23	Evening	t
1119	37	2024-11-23	Night	t
1120	37	2024-11-23	Midnight	t
1121	38	2024-11-23	Early Morning	t
1122	38	2024-11-23	Morning	t
1123	38	2024-11-23	Noon	t
1124	38	2024-11-23	Afternoon	t
1125	38	2024-11-23	Evening	t
1126	38	2024-11-23	Night	t
1127	38	2024-11-23	Midnight	t
1128	39	2024-11-23	Early Morning	t
1129	39	2024-11-23	Morning	t
1130	39	2024-11-23	Noon	t
1131	39	2024-11-23	Afternoon	t
1132	39	2024-11-23	Evening	t
1133	39	2024-11-23	Night	t
1134	39	2024-11-23	Midnight	t
1135	40	2024-11-23	Early Morning	t
1136	40	2024-11-23	Morning	t
1137	40	2024-11-23	Noon	t
1138	40	2024-11-23	Afternoon	t
1139	40	2024-11-23	Evening	t
1140	40	2024-11-23	Night	t
1141	40	2024-11-23	Midnight	t
1142	41	2024-11-23	Early Morning	t
1143	41	2024-11-23	Morning	t
1144	41	2024-11-23	Noon	t
1145	41	2024-11-23	Afternoon	t
1146	41	2024-11-23	Evening	t
1147	41	2024-11-23	Night	t
1148	41	2024-11-23	Midnight	t
1149	1	2024-11-24	Early Morning	t
1150	1	2024-11-24	Morning	t
1151	1	2024-11-24	Noon	t
1152	1	2024-11-24	Afternoon	t
1153	1	2024-11-24	Evening	t
1154	1	2024-11-24	Night	t
1155	1	2024-11-24	Midnight	t
1156	2	2024-11-24	Early Morning	t
1157	2	2024-11-24	Morning	t
1158	2	2024-11-24	Noon	t
1159	2	2024-11-24	Afternoon	t
1160	2	2024-11-24	Evening	t
1161	2	2024-11-24	Night	t
1162	2	2024-11-24	Midnight	t
1163	3	2024-11-24	Early Morning	t
1164	3	2024-11-24	Morning	t
1165	3	2024-11-24	Noon	t
1166	3	2024-11-24	Afternoon	t
1167	3	2024-11-24	Evening	t
1168	3	2024-11-24	Night	t
1169	3	2024-11-24	Midnight	t
1170	4	2024-11-24	Early Morning	t
1171	4	2024-11-24	Morning	t
1172	4	2024-11-24	Noon	t
1173	4	2024-11-24	Afternoon	t
1174	4	2024-11-24	Evening	t
1175	4	2024-11-24	Night	t
1176	4	2024-11-24	Midnight	t
1177	5	2024-11-24	Early Morning	t
1178	5	2024-11-24	Morning	t
1179	5	2024-11-24	Noon	t
1180	5	2024-11-24	Afternoon	t
1181	5	2024-11-24	Evening	t
1182	5	2024-11-24	Night	t
1183	5	2024-11-24	Midnight	t
1184	6	2024-11-24	Early Morning	t
1185	6	2024-11-24	Morning	t
1186	6	2024-11-24	Noon	t
1187	6	2024-11-24	Afternoon	t
1188	6	2024-11-24	Evening	t
1189	6	2024-11-24	Night	t
1190	6	2024-11-24	Midnight	t
1191	7	2024-11-24	Early Morning	t
1192	7	2024-11-24	Morning	t
1193	7	2024-11-24	Noon	t
1194	7	2024-11-24	Afternoon	t
1195	7	2024-11-24	Evening	t
1196	7	2024-11-24	Night	t
1197	7	2024-11-24	Midnight	t
1198	8	2024-11-24	Early Morning	t
1199	8	2024-11-24	Morning	t
1200	8	2024-11-24	Noon	t
1201	8	2024-11-24	Afternoon	t
1202	8	2024-11-24	Evening	t
1203	8	2024-11-24	Night	t
1204	8	2024-11-24	Midnight	t
1205	9	2024-11-24	Early Morning	t
1206	9	2024-11-24	Morning	t
1207	9	2024-11-24	Noon	t
1208	9	2024-11-24	Afternoon	t
1209	9	2024-11-24	Evening	t
1210	9	2024-11-24	Night	t
1211	9	2024-11-24	Midnight	t
1212	10	2024-11-24	Early Morning	t
1213	10	2024-11-24	Morning	t
1214	10	2024-11-24	Noon	t
1215	10	2024-11-24	Afternoon	t
1216	10	2024-11-24	Evening	t
1217	10	2024-11-24	Night	t
1218	10	2024-11-24	Midnight	t
1219	11	2024-11-24	Early Morning	t
1220	11	2024-11-24	Morning	t
1221	11	2024-11-24	Noon	t
1222	11	2024-11-24	Afternoon	t
1223	11	2024-11-24	Evening	t
1224	11	2024-11-24	Night	t
1225	11	2024-11-24	Midnight	t
1226	12	2024-11-24	Early Morning	t
1227	12	2024-11-24	Morning	t
1228	12	2024-11-24	Noon	t
1229	12	2024-11-24	Afternoon	t
1230	12	2024-11-24	Evening	t
1231	12	2024-11-24	Night	t
1232	12	2024-11-24	Midnight	t
1233	13	2024-11-24	Early Morning	t
1234	13	2024-11-24	Morning	t
1235	13	2024-11-24	Noon	t
1236	13	2024-11-24	Afternoon	t
1237	13	2024-11-24	Evening	t
1238	13	2024-11-24	Night	t
1239	13	2024-11-24	Midnight	t
1240	14	2024-11-24	Early Morning	t
1241	14	2024-11-24	Morning	t
1242	14	2024-11-24	Noon	t
1243	14	2024-11-24	Afternoon	t
1244	14	2024-11-24	Evening	t
1245	14	2024-11-24	Night	t
1246	14	2024-11-24	Midnight	t
1247	15	2024-11-24	Early Morning	t
1248	15	2024-11-24	Morning	t
1249	15	2024-11-24	Noon	t
1250	15	2024-11-24	Afternoon	t
1251	15	2024-11-24	Evening	t
1252	15	2024-11-24	Night	t
1253	15	2024-11-24	Midnight	t
1254	16	2024-11-24	Early Morning	t
1255	16	2024-11-24	Morning	t
1256	16	2024-11-24	Noon	t
1257	16	2024-11-24	Afternoon	t
1258	16	2024-11-24	Evening	t
1259	16	2024-11-24	Night	t
1260	16	2024-11-24	Midnight	t
1261	17	2024-11-24	Early Morning	t
1262	17	2024-11-24	Morning	t
1263	17	2024-11-24	Noon	t
1264	17	2024-11-24	Afternoon	t
1265	17	2024-11-24	Evening	t
1266	17	2024-11-24	Night	t
1267	17	2024-11-24	Midnight	t
1268	18	2024-11-24	Early Morning	t
1269	18	2024-11-24	Morning	t
1270	18	2024-11-24	Noon	t
1271	18	2024-11-24	Afternoon	t
1272	18	2024-11-24	Evening	t
1273	18	2024-11-24	Night	t
1274	18	2024-11-24	Midnight	t
1275	19	2024-11-24	Early Morning	t
1276	19	2024-11-24	Morning	t
1277	19	2024-11-24	Noon	t
1278	19	2024-11-24	Afternoon	t
1279	19	2024-11-24	Evening	t
1280	19	2024-11-24	Night	t
1281	19	2024-11-24	Midnight	t
1282	20	2024-11-24	Early Morning	t
1283	20	2024-11-24	Morning	t
1284	20	2024-11-24	Noon	t
1285	20	2024-11-24	Afternoon	t
1286	20	2024-11-24	Evening	t
1287	20	2024-11-24	Night	t
1288	20	2024-11-24	Midnight	t
1289	21	2024-11-24	Early Morning	t
1290	21	2024-11-24	Morning	t
1291	21	2024-11-24	Noon	t
1292	21	2024-11-24	Afternoon	t
1293	21	2024-11-24	Evening	t
1294	21	2024-11-24	Night	t
1295	21	2024-11-24	Midnight	t
1296	22	2024-11-24	Early Morning	t
1297	22	2024-11-24	Morning	t
1298	22	2024-11-24	Noon	t
1299	22	2024-11-24	Afternoon	t
1300	22	2024-11-24	Evening	t
1301	22	2024-11-24	Night	t
1302	22	2024-11-24	Midnight	t
1303	23	2024-11-24	Early Morning	t
1304	23	2024-11-24	Morning	t
1305	23	2024-11-24	Noon	t
1306	23	2024-11-24	Afternoon	t
1307	23	2024-11-24	Evening	t
1308	23	2024-11-24	Night	t
1309	23	2024-11-24	Midnight	t
1310	24	2024-11-24	Early Morning	t
1311	24	2024-11-24	Morning	t
1312	24	2024-11-24	Noon	t
1313	24	2024-11-24	Afternoon	t
1314	24	2024-11-24	Evening	t
1315	24	2024-11-24	Night	t
1316	24	2024-11-24	Midnight	t
1317	25	2024-11-24	Early Morning	t
1318	25	2024-11-24	Morning	t
1319	25	2024-11-24	Noon	t
1320	25	2024-11-24	Afternoon	t
1321	25	2024-11-24	Evening	t
1322	25	2024-11-24	Night	t
1323	25	2024-11-24	Midnight	t
1324	26	2024-11-24	Early Morning	t
1325	26	2024-11-24	Morning	t
1326	26	2024-11-24	Noon	t
1327	26	2024-11-24	Afternoon	t
1328	26	2024-11-24	Evening	t
1329	26	2024-11-24	Night	t
1330	26	2024-11-24	Midnight	t
1331	27	2024-11-24	Early Morning	t
1332	27	2024-11-24	Morning	t
1333	27	2024-11-24	Noon	t
1334	27	2024-11-24	Afternoon	t
1335	27	2024-11-24	Evening	t
1336	27	2024-11-24	Night	t
1337	27	2024-11-24	Midnight	t
1338	28	2024-11-24	Early Morning	t
1339	28	2024-11-24	Morning	t
1340	28	2024-11-24	Noon	t
1341	28	2024-11-24	Afternoon	t
1342	28	2024-11-24	Evening	t
1343	28	2024-11-24	Night	t
1344	28	2024-11-24	Midnight	t
1345	29	2024-11-24	Early Morning	t
1346	29	2024-11-24	Morning	t
1347	29	2024-11-24	Noon	t
1348	29	2024-11-24	Afternoon	t
1349	29	2024-11-24	Evening	t
1350	29	2024-11-24	Night	t
1351	29	2024-11-24	Midnight	t
1352	30	2024-11-24	Early Morning	t
1353	30	2024-11-24	Morning	t
1354	30	2024-11-24	Noon	t
1355	30	2024-11-24	Afternoon	t
1356	30	2024-11-24	Evening	t
1357	30	2024-11-24	Night	t
1358	30	2024-11-24	Midnight	t
1359	31	2024-11-24	Early Morning	t
1360	31	2024-11-24	Morning	t
1361	31	2024-11-24	Noon	t
1362	31	2024-11-24	Afternoon	t
1363	31	2024-11-24	Evening	t
1364	31	2024-11-24	Night	t
1365	31	2024-11-24	Midnight	t
1366	32	2024-11-24	Early Morning	t
1367	32	2024-11-24	Morning	t
1368	32	2024-11-24	Noon	t
1369	32	2024-11-24	Afternoon	t
1370	32	2024-11-24	Evening	t
1371	32	2024-11-24	Night	t
1372	32	2024-11-24	Midnight	t
1373	33	2024-11-24	Early Morning	t
1374	33	2024-11-24	Morning	t
1375	33	2024-11-24	Noon	t
1376	33	2024-11-24	Afternoon	t
1377	33	2024-11-24	Evening	t
1378	33	2024-11-24	Night	t
1379	33	2024-11-24	Midnight	t
1380	34	2024-11-24	Early Morning	t
1381	34	2024-11-24	Morning	t
1382	34	2024-11-24	Noon	t
1383	34	2024-11-24	Afternoon	t
1384	34	2024-11-24	Evening	t
1385	34	2024-11-24	Night	t
1386	34	2024-11-24	Midnight	t
1387	35	2024-11-24	Early Morning	t
1388	35	2024-11-24	Morning	t
1389	35	2024-11-24	Noon	t
1390	35	2024-11-24	Afternoon	t
1391	35	2024-11-24	Evening	t
1392	35	2024-11-24	Night	t
1393	35	2024-11-24	Midnight	t
1394	36	2024-11-24	Early Morning	t
1395	36	2024-11-24	Morning	t
1396	36	2024-11-24	Noon	t
1397	36	2024-11-24	Afternoon	t
1398	36	2024-11-24	Evening	t
1399	36	2024-11-24	Night	t
1400	36	2024-11-24	Midnight	t
1401	37	2024-11-24	Early Morning	t
1402	37	2024-11-24	Morning	t
1403	37	2024-11-24	Noon	t
1404	37	2024-11-24	Afternoon	t
1405	37	2024-11-24	Evening	t
1406	37	2024-11-24	Night	t
1407	37	2024-11-24	Midnight	t
1408	38	2024-11-24	Early Morning	t
1409	38	2024-11-24	Morning	t
1410	38	2024-11-24	Noon	t
1411	38	2024-11-24	Afternoon	t
1412	38	2024-11-24	Evening	t
1413	38	2024-11-24	Night	t
1414	38	2024-11-24	Midnight	t
1415	39	2024-11-24	Early Morning	t
1416	39	2024-11-24	Morning	t
1417	39	2024-11-24	Noon	t
1418	39	2024-11-24	Afternoon	t
1419	39	2024-11-24	Evening	t
1420	39	2024-11-24	Night	t
1421	39	2024-11-24	Midnight	t
1422	40	2024-11-24	Early Morning	t
1423	40	2024-11-24	Morning	t
1424	40	2024-11-24	Noon	t
1425	40	2024-11-24	Afternoon	t
1426	40	2024-11-24	Evening	t
1427	40	2024-11-24	Night	t
1428	40	2024-11-24	Midnight	t
1429	41	2024-11-24	Early Morning	t
1430	41	2024-11-24	Morning	t
1431	41	2024-11-24	Noon	t
1432	41	2024-11-24	Afternoon	t
1433	41	2024-11-24	Evening	t
1434	41	2024-11-24	Night	t
1435	41	2024-11-24	Midnight	t
1436	1	2024-11-25	Early Morning	t
1437	1	2024-11-25	Morning	t
1438	1	2024-11-25	Noon	t
1439	1	2024-11-25	Afternoon	t
1440	1	2024-11-25	Evening	t
1441	1	2024-11-25	Night	t
1442	1	2024-11-25	Midnight	t
1443	2	2024-11-25	Early Morning	t
1444	2	2024-11-25	Morning	t
1445	2	2024-11-25	Noon	t
1446	2	2024-11-25	Afternoon	t
1447	2	2024-11-25	Evening	t
1448	2	2024-11-25	Night	t
1449	2	2024-11-25	Midnight	t
1450	3	2024-11-25	Early Morning	t
1451	3	2024-11-25	Morning	t
1452	3	2024-11-25	Noon	t
1453	3	2024-11-25	Afternoon	t
1454	3	2024-11-25	Evening	t
1455	3	2024-11-25	Night	t
1456	3	2024-11-25	Midnight	t
1457	4	2024-11-25	Early Morning	t
1458	4	2024-11-25	Morning	t
1459	4	2024-11-25	Noon	t
1460	4	2024-11-25	Afternoon	t
1461	4	2024-11-25	Evening	t
1462	4	2024-11-25	Night	t
1463	4	2024-11-25	Midnight	t
1464	5	2024-11-25	Early Morning	t
1465	5	2024-11-25	Morning	t
1466	5	2024-11-25	Noon	t
1467	5	2024-11-25	Afternoon	t
1468	5	2024-11-25	Evening	t
1469	5	2024-11-25	Night	t
1470	5	2024-11-25	Midnight	t
1471	6	2024-11-25	Early Morning	t
1472	6	2024-11-25	Morning	t
1473	6	2024-11-25	Noon	t
1474	6	2024-11-25	Afternoon	t
1475	6	2024-11-25	Evening	t
1476	6	2024-11-25	Night	t
1477	6	2024-11-25	Midnight	t
1478	7	2024-11-25	Early Morning	t
1479	7	2024-11-25	Morning	t
1480	7	2024-11-25	Noon	t
1481	7	2024-11-25	Afternoon	t
1482	7	2024-11-25	Evening	t
1483	7	2024-11-25	Night	t
1484	7	2024-11-25	Midnight	t
1485	8	2024-11-25	Early Morning	t
1486	8	2024-11-25	Morning	t
1487	8	2024-11-25	Noon	t
1488	8	2024-11-25	Afternoon	t
1489	8	2024-11-25	Evening	t
1490	8	2024-11-25	Night	t
1491	8	2024-11-25	Midnight	t
1492	9	2024-11-25	Early Morning	t
1493	9	2024-11-25	Morning	t
1494	9	2024-11-25	Noon	t
1495	9	2024-11-25	Afternoon	t
1496	9	2024-11-25	Evening	t
1497	9	2024-11-25	Night	t
1498	9	2024-11-25	Midnight	t
1499	10	2024-11-25	Early Morning	t
1500	10	2024-11-25	Morning	t
1501	10	2024-11-25	Noon	t
1502	10	2024-11-25	Afternoon	t
1503	10	2024-11-25	Evening	t
1504	10	2024-11-25	Night	t
1505	10	2024-11-25	Midnight	t
1506	11	2024-11-25	Early Morning	t
1507	11	2024-11-25	Morning	t
1508	11	2024-11-25	Noon	t
1509	11	2024-11-25	Afternoon	t
1510	11	2024-11-25	Evening	t
1511	11	2024-11-25	Night	t
1512	11	2024-11-25	Midnight	t
1513	12	2024-11-25	Early Morning	t
1514	12	2024-11-25	Morning	t
1515	12	2024-11-25	Noon	t
1516	12	2024-11-25	Afternoon	t
1517	12	2024-11-25	Evening	t
1518	12	2024-11-25	Night	t
1519	12	2024-11-25	Midnight	t
1520	13	2024-11-25	Early Morning	t
1521	13	2024-11-25	Morning	t
1522	13	2024-11-25	Noon	t
1523	13	2024-11-25	Afternoon	t
1524	13	2024-11-25	Evening	t
1525	13	2024-11-25	Night	t
1526	13	2024-11-25	Midnight	t
1527	14	2024-11-25	Early Morning	t
1528	14	2024-11-25	Morning	t
1529	14	2024-11-25	Noon	t
1530	14	2024-11-25	Afternoon	t
1531	14	2024-11-25	Evening	t
1532	14	2024-11-25	Night	t
1533	14	2024-11-25	Midnight	t
1534	15	2024-11-25	Early Morning	t
1535	15	2024-11-25	Morning	t
1536	15	2024-11-25	Noon	t
1537	15	2024-11-25	Afternoon	t
1538	15	2024-11-25	Evening	t
1539	15	2024-11-25	Night	t
1540	15	2024-11-25	Midnight	t
1541	16	2024-11-25	Early Morning	t
1542	16	2024-11-25	Morning	t
1543	16	2024-11-25	Noon	t
1544	16	2024-11-25	Afternoon	t
1545	16	2024-11-25	Evening	t
1546	16	2024-11-25	Night	t
1547	16	2024-11-25	Midnight	t
1548	17	2024-11-25	Early Morning	t
1549	17	2024-11-25	Morning	t
1550	17	2024-11-25	Noon	t
1551	17	2024-11-25	Afternoon	t
1552	17	2024-11-25	Evening	t
1553	17	2024-11-25	Night	t
1554	17	2024-11-25	Midnight	t
1555	18	2024-11-25	Early Morning	t
1556	18	2024-11-25	Morning	t
1557	18	2024-11-25	Noon	t
1558	18	2024-11-25	Afternoon	t
1559	18	2024-11-25	Evening	t
1560	18	2024-11-25	Night	t
1561	18	2024-11-25	Midnight	t
1562	19	2024-11-25	Early Morning	t
1563	19	2024-11-25	Morning	t
1564	19	2024-11-25	Noon	t
1565	19	2024-11-25	Afternoon	t
1566	19	2024-11-25	Evening	t
1567	19	2024-11-25	Night	t
1568	19	2024-11-25	Midnight	t
1569	20	2024-11-25	Early Morning	t
1570	20	2024-11-25	Morning	t
1571	20	2024-11-25	Noon	t
1572	20	2024-11-25	Afternoon	t
1573	20	2024-11-25	Evening	t
1574	20	2024-11-25	Night	t
1575	20	2024-11-25	Midnight	t
1576	21	2024-11-25	Early Morning	t
1577	21	2024-11-25	Morning	t
1578	21	2024-11-25	Noon	t
1579	21	2024-11-25	Afternoon	t
1580	21	2024-11-25	Evening	t
1581	21	2024-11-25	Night	t
1582	21	2024-11-25	Midnight	t
1583	22	2024-11-25	Early Morning	t
1584	22	2024-11-25	Morning	t
1585	22	2024-11-25	Noon	t
1586	22	2024-11-25	Afternoon	t
1587	22	2024-11-25	Evening	t
1588	22	2024-11-25	Night	t
1589	22	2024-11-25	Midnight	t
1590	23	2024-11-25	Early Morning	t
1591	23	2024-11-25	Morning	t
1592	23	2024-11-25	Noon	t
1593	23	2024-11-25	Afternoon	t
1594	23	2024-11-25	Evening	t
1595	23	2024-11-25	Night	t
1596	23	2024-11-25	Midnight	t
1597	24	2024-11-25	Early Morning	t
1598	24	2024-11-25	Morning	t
1599	24	2024-11-25	Noon	t
1600	24	2024-11-25	Afternoon	t
1601	24	2024-11-25	Evening	t
1602	24	2024-11-25	Night	t
1603	24	2024-11-25	Midnight	t
1604	25	2024-11-25	Early Morning	t
1605	25	2024-11-25	Morning	t
1606	25	2024-11-25	Noon	t
1607	25	2024-11-25	Afternoon	t
1608	25	2024-11-25	Evening	t
1609	25	2024-11-25	Night	t
1610	25	2024-11-25	Midnight	t
1611	26	2024-11-25	Early Morning	t
1612	26	2024-11-25	Morning	t
1613	26	2024-11-25	Noon	t
1614	26	2024-11-25	Afternoon	t
1615	26	2024-11-25	Evening	t
1616	26	2024-11-25	Night	t
1617	26	2024-11-25	Midnight	t
1618	27	2024-11-25	Early Morning	t
1619	27	2024-11-25	Morning	t
1620	27	2024-11-25	Noon	t
1621	27	2024-11-25	Afternoon	t
1622	27	2024-11-25	Evening	t
1623	27	2024-11-25	Night	t
1624	27	2024-11-25	Midnight	t
1625	28	2024-11-25	Early Morning	t
1626	28	2024-11-25	Morning	t
1627	28	2024-11-25	Noon	t
1628	28	2024-11-25	Afternoon	t
1629	28	2024-11-25	Evening	t
1630	28	2024-11-25	Night	t
1631	28	2024-11-25	Midnight	t
1632	29	2024-11-25	Early Morning	t
1633	29	2024-11-25	Morning	t
1634	29	2024-11-25	Noon	t
1635	29	2024-11-25	Afternoon	t
1636	29	2024-11-25	Evening	t
1637	29	2024-11-25	Night	t
1638	29	2024-11-25	Midnight	t
1639	30	2024-11-25	Early Morning	t
1640	30	2024-11-25	Morning	t
1641	30	2024-11-25	Noon	t
1642	30	2024-11-25	Afternoon	t
1643	30	2024-11-25	Evening	t
1644	30	2024-11-25	Night	t
1645	30	2024-11-25	Midnight	t
1646	31	2024-11-25	Early Morning	t
1647	31	2024-11-25	Morning	t
1648	31	2024-11-25	Noon	t
1649	31	2024-11-25	Afternoon	t
1650	31	2024-11-25	Evening	t
1651	31	2024-11-25	Night	t
1652	31	2024-11-25	Midnight	t
1653	32	2024-11-25	Early Morning	t
1654	32	2024-11-25	Morning	t
1655	32	2024-11-25	Noon	t
1656	32	2024-11-25	Afternoon	t
1657	32	2024-11-25	Evening	t
1658	32	2024-11-25	Night	t
1659	32	2024-11-25	Midnight	t
1660	33	2024-11-25	Early Morning	t
1661	33	2024-11-25	Morning	t
1662	33	2024-11-25	Noon	t
1663	33	2024-11-25	Afternoon	t
1664	33	2024-11-25	Evening	t
1665	33	2024-11-25	Night	t
1666	33	2024-11-25	Midnight	t
1667	34	2024-11-25	Early Morning	t
1668	34	2024-11-25	Morning	t
1669	34	2024-11-25	Noon	t
1670	34	2024-11-25	Afternoon	t
1671	34	2024-11-25	Evening	t
1672	34	2024-11-25	Night	t
1673	34	2024-11-25	Midnight	t
1674	35	2024-11-25	Early Morning	t
1675	35	2024-11-25	Morning	t
1676	35	2024-11-25	Noon	t
1677	35	2024-11-25	Afternoon	t
1678	35	2024-11-25	Evening	t
1679	35	2024-11-25	Night	t
1680	35	2024-11-25	Midnight	t
1681	36	2024-11-25	Early Morning	t
1682	36	2024-11-25	Morning	t
1683	36	2024-11-25	Noon	t
1684	36	2024-11-25	Afternoon	t
1685	36	2024-11-25	Evening	t
1686	36	2024-11-25	Night	t
1687	36	2024-11-25	Midnight	t
1688	37	2024-11-25	Early Morning	t
1689	37	2024-11-25	Morning	t
1690	37	2024-11-25	Noon	t
1691	37	2024-11-25	Afternoon	t
1692	37	2024-11-25	Evening	t
1693	37	2024-11-25	Night	t
1694	37	2024-11-25	Midnight	t
1695	38	2024-11-25	Early Morning	t
1696	38	2024-11-25	Morning	t
1697	38	2024-11-25	Noon	t
1698	38	2024-11-25	Afternoon	t
1699	38	2024-11-25	Evening	t
1700	38	2024-11-25	Night	t
1701	38	2024-11-25	Midnight	t
1702	39	2024-11-25	Early Morning	t
1703	39	2024-11-25	Morning	t
1704	39	2024-11-25	Noon	t
1705	39	2024-11-25	Afternoon	t
1706	39	2024-11-25	Evening	t
1707	39	2024-11-25	Night	t
1708	39	2024-11-25	Midnight	t
1709	40	2024-11-25	Early Morning	t
1710	40	2024-11-25	Morning	t
1711	40	2024-11-25	Noon	t
1712	40	2024-11-25	Afternoon	t
1713	40	2024-11-25	Evening	t
1714	40	2024-11-25	Night	t
1715	40	2024-11-25	Midnight	t
1716	41	2024-11-25	Early Morning	t
1717	41	2024-11-25	Morning	t
1718	41	2024-11-25	Noon	t
1719	41	2024-11-25	Afternoon	t
1720	41	2024-11-25	Evening	t
1721	41	2024-11-25	Night	t
1722	41	2024-11-25	Midnight	t
30	5	2024-11-20	Morning	f
330	7	2024-11-21	Early Morning	f
498	31	2024-11-21	Early Morning	f
291	1	2024-11-21	Afternoon	f
\.


--
-- Data for Name: bookings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bookings (booking_id, ground_id, user_id, booking_date, time_slot, booking_timestamp, status) FROM stdin;
3	5	1	2024-11-20	Morning	2024-11-19 06:00:40.584787	Confirmed
13	5	1	2024-11-20	Early Morning	2024-11-20 04:37:57.76096	Confirmed
14	10	1	2024-11-20	Afternoon	2024-11-20 04:37:57.76096	Confirmed
15	18	1	2024-11-20	Night	2024-11-20 04:37:57.76096	Confirmed
16	3	1	2024-11-20	Morning	2024-11-20 04:37:57.76096	Confirmed
17	20	1	2024-11-20	Midnight	2024-11-20 04:37:57.76096	Confirmed
18	3	2	2024-11-20	Morning	2024-11-20 04:37:57.76096	Confirmed
19	7	2	2024-11-20	Noon	2024-11-20 04:37:57.76096	Confirmed
20	12	2	2024-11-20	Evening	2024-11-20 04:37:57.76096	Confirmed
21	17	2	2024-11-20	Midnight	2024-11-20 04:37:57.76096	Confirmed
22	22	2	2024-11-20	Night	2024-11-20 04:37:57.76096	Confirmed
23	8	3	2024-11-20	Morning	2024-11-20 04:37:57.76096	Confirmed
24	13	3	2024-11-20	Evening	2024-11-20 04:37:57.76096	Confirmed
25	14	3	2024-11-20	Night	2024-11-20 04:37:57.76096	Confirmed
26	15	4	2024-11-20	Early Morning	2024-11-20 04:37:57.76096	Confirmed
27	20	4	2024-11-20	Morning	2024-11-20 04:37:57.76096	Confirmed
28	25	4	2024-11-20	Afternoon	2024-11-20 04:37:57.76096	Confirmed
29	30	4	2024-11-20	Noon	2024-11-20 04:37:57.76096	Confirmed
30	5	4	2024-11-20	Evening	2024-11-20 04:37:57.76096	Confirmed
31	2	4	2024-11-20	Night	2024-11-20 04:37:57.76096	Confirmed
32	3	5	2024-11-20	Night	2024-11-20 04:37:57.76096	Confirmed
33	19	5	2024-11-20	Midnight	2024-11-20 04:37:57.76096	Confirmed
34	11	5	2024-11-20	Early Morning	2024-11-20 04:37:57.76096	Confirmed
35	2	6	2024-11-20	Early Morning	2024-11-20 04:37:57.76096	Confirmed
36	9	6	2024-11-20	Morning	2024-11-20 04:37:57.76096	Confirmed
37	14	6	2024-11-20	Noon	2024-11-20 04:37:57.76096	Confirmed
38	17	6	2024-11-20	Afternoon	2024-11-20 04:37:57.76096	Confirmed
39	22	6	2024-11-20	Evening	2024-11-20 04:37:57.76096	Confirmed
40	25	6	2024-11-20	Night	2024-11-20 04:37:57.76096	Confirmed
41	31	6	2024-11-20	Midnight	2024-11-20 04:37:57.76096	Confirmed
42	5	7	2024-11-20	Afternoon	2024-11-20 04:37:57.76096	Confirmed
43	16	7	2024-11-20	Morning	2024-11-20 04:37:57.76096	Confirmed
44	10	8	2024-11-20	Early Morning	2024-11-20 04:37:57.76096	Confirmed
45	12	8	2024-11-20	Afternoon	2024-11-20 04:37:57.76096	Confirmed
46	19	8	2024-11-20	Evening	2024-11-20 04:37:57.76096	Confirmed
47	27	8	2024-11-20	Night	2024-11-20 04:37:57.76096	Confirmed
48	15	9	2024-11-20	Morning	2024-11-20 04:37:57.76096	Confirmed
49	20	9	2024-11-20	Noon	2024-11-20 04:37:57.76096	Confirmed
50	25	9	2024-11-20	Afternoon	2024-11-20 04:37:57.76096	Confirmed
51	30	9	2024-11-20	Evening	2024-11-20 04:37:57.76096	Confirmed
52	3	9	2024-11-20	Night	2024-11-20 04:37:57.76096	Confirmed
53	4	9	2024-11-20	Midnight	2024-11-20 04:37:57.76096	Confirmed
54	18	10	2024-11-20	Early Morning	2024-11-20 04:37:57.76096	Confirmed
55	7	10	2024-11-20	Midnight	2024-11-20 04:37:57.76096	Confirmed
56	10	10	2024-11-20	Morning	2024-11-20 04:37:57.76096	Confirmed
57	21	10	2024-11-20	Afternoon	2024-11-20 04:37:57.76096	Confirmed
58	5	1	2024-11-20	Morning	2024-11-20 04:45:46.683117	Confirmed
59	5	1	2024-11-20	Morning	2024-11-20 04:48:50.198402	Confirmed
60	5	1	2024-11-20	Morning	2024-11-20 04:50:34.550768	Confirmed
67	7	1	2024-11-21	Early Morning	2024-11-20 06:35:36.129774	Confirmed
68	31	8	2024-11-21	Early Morning	2024-11-20 06:43:58.184544	Confirmed
69	27	1	2024-11-21	Evening	2024-11-20 06:53:21.026654	Confirmed
70	13	1	2024-11-21	Early Morning	2024-11-20 10:50:23.828565	Confirmed
71	1	1	2024-11-21	Afternoon	2024-11-20 11:26:01.485948	Confirmed
72	13	1	2024-11-21	Midnight	2024-11-21 11:04:11.552608	Confirmed
73	13	1	2024-11-21	Evening	2024-11-21 11:16:23.591599	Confirmed
74	1	1	2024-11-21	Night	2024-11-21 11:27:41.924656	Confirmed
75	10	1	2024-11-21	Afternoon	2024-11-21 11:33:01.868917	Confirmed
76	28	1	2024-11-21	Midnight	2024-11-21 11:44:22.805693	Confirmed
77	10	1	2024-11-21	Night	2024-11-23 19:47:46.937006	Confirmed
\.


--
-- Data for Name: grounds; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.grounds (ground_id, ground_name, location, sport_type, creator_id, priority) FROM stdin;
27	Pioneer Grounds	Banashankari	Badminton	11	98
16	Horizon Ground	Indirangar	Football	12	100
18	Power Court	Banashankari	Badminton	12	100
20	Peak Field	Koramangala	Cricket	12	100
22	Thunder Field	Indirangar	Football	12	100
24	Champion Court	Banashankari	Badminton	12	100
26	Sapphire Field	Koramangala	Cricket	12	100
28	Legends Field	Indirangar	Football	12	100
30	Skyline Court	Banashankari	Badminton	12	100
32	Maverick Court	Koramangala	Cricket	12	100
34	Fusion Arena	Indirangar	Football	12	100
36	Thunder Park	Banashankari	Badminton	12	100
38	Pioneer Park	Koramangala	Cricket	12	100
40	Galaxy Ground	Indirangar	Football	12	100
41	Noble Arena	Koramangala	Cricket	11	100
15	Star Court	Banashankari	Badminton	11	99
7	Silver Grass Ground	Indirangar	Football	11	99
5	Champion Stadium	Koramangala	Cricket	11	95
19	Blue Sky Stadium	Indirangar	Football	11	99
25	Royal Arena	Indirangar	Football	11	98
31	Victory Fields	Indirangar	Football	11	99
33	Legend Court	Banashankari	Badminton	11	99
11	Victory Grounds	Koramangala	Cricket	11	96
23	Emerald Park	Koramangala	Cricket	11	98
12	Diamond Court	Banashankari	Badminton	12	99
14	Sunrise Park	Koramangala	Cricket	12	99
10	Eagle Eye Field	Indirangar	Football	12	98
8	Golden Meadow	Koramangala	Cricket	12	98
6	Ace Arena	Banashankari	Badminton	12	99
2	Victory Park	Koramangala	Cricket	12	98
4	Riverside Field	Indirangar	Football	12	97
35	Diamond Grounds	Koramangala	Cricket	11	99
37	Sunrise Court	Indirangar	Football	11	98
9	Majestic Field	Banashankari	Badminton	11	97
13	Highland Arena	Indirangar	Football	11	97
17	Prime Field	Koramangala	Cricket	11	97
1	Sunset Arena	Indirangar	Football	11	89
39	Majestic Court	Banashankari	Badminton	11	99
29	Sunbeam Arena	Koramangala	Cricket	11	97
3	Thunder Court	Banashankari	Badminton	11	98
21	Olympus Court	Banashankari	Badminton	11	97
\.


--
-- Data for Name: promotions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.promotions (promotion_id, ground_id, creator_id, status, promotion_date, details) FROM stdin;
1	5	11	Approved	2024-11-19 09:18:01.002192	Promotion for Champion Stadium
2	3	11	Approved	2024-11-19 10:01:32.581691	Promotion for Thunder Court
3	5	11	Approved	2024-11-19 10:01:35.195756	Promotion for Champion Stadium
4	7	11	Approved	2024-11-19 10:01:37.23211	Promotion for Silver Grass Ground
5	9	11	Approved	2024-11-19 10:01:39.124324	Promotion for Majestic Field
6	11	11	Approved	2024-11-19 10:01:40.824094	Promotion for Victory Grounds
7	13	11	Approved	2024-11-19 10:01:43.683554	Promotion for Highland Arena
8	9	11	Approved	2024-11-19 10:02:06.981941	Promotion for Majestic Field
9	5	11	Approved	2024-11-19 10:02:34.764969	Promotion for Champion Stadium
10	5	11	Approved	2024-11-19 10:02:35.428746	Promotion for Champion Stadium
11	5	11	Approved	2024-11-19 10:02:36.062366	Promotion for Champion Stadium
12	2	12	Approved	2024-11-19 10:46:02.115681	Promotion for Victory Park
13	2	12	Approved	2024-11-19 10:46:03.709123	Promotion for Victory Park
14	2	12	Approved	2024-11-19 10:46:03.952668	Promotion for Victory Park
15	2	12	Approved	2024-11-19 10:46:04.221181	Promotion for Victory Park
16	2	12	Approved	2024-11-19 10:46:04.454758	Promotion for Victory Park
17	4	12	Approved	2024-11-19 10:46:05.130656	Promotion for Riverside Field
18	6	12	Approved	2024-11-19 10:46:05.752377	Promotion for Ace Arena
19	8	12	Approved	2024-11-19 10:46:06.432668	Promotion for Golden Meadow
20	6	12	Approved	2024-11-19 10:46:07.339002	Promotion for Ace Arena
21	4	12	Approved	2024-11-19 10:46:08.115943	Promotion for Riverside Field
22	12	12	Approved	2024-11-19 10:46:17.053373	Promotion for Diamond Court
23	16	12	Approved	2024-11-19 10:46:19.386412	Promotion for Horizon Ground
24	19	11	Approved	2024-11-19 10:46:50.041896	Promotion for Blue Sky Stadium
25	21	11	Approved	2024-11-19 10:46:51.10751	Promotion for Olympus Court
26	23	11	Approved	2024-11-19 10:46:52.608266	Promotion for Emerald Park
27	17	11	Approved	2024-11-19 10:46:53.408003	Promotion for Prime Field
28	29	11	Approved	2024-11-19 10:46:58.058716	Promotion for Sunbeam Arena
29	25	11	Approved	2024-11-19 10:46:59.345647	Promotion for Royal Arena
30	11	11	Approved	2024-11-19 10:47:04.382029	Promotion for Victory Grounds
31	4	12	Approved	2024-11-19 10:50:45.352922	Promotion for Riverside Field
32	6	12	Approved	2024-11-19 10:50:46.299925	Promotion for Ace Arena
33	2	12	Approved	2024-11-19 10:50:47.217126	Promotion for Victory Park
34	8	12	Approved	2024-11-19 10:50:48.149935	Promotion for Golden Meadow
35	10	12	Approved	2024-11-19 10:50:48.895581	Promotion for Eagle Eye Field
36	12	12	Approved	2024-11-19 10:50:49.678037	Promotion for Diamond Court
37	14	12	Approved	2024-11-19 10:51:20.918974	Promotion for Sunrise Park
38	11	11	Approved	2024-11-19 10:52:13.306853	Promotion for Victory Grounds
39	15	11	Approved	2024-11-19 10:52:14.010117	Promotion for Star Court
40	29	11	Approved	2024-11-19 10:52:14.684739	Promotion for Sunbeam Arena
41	17	11	Approved	2024-11-19 10:52:15.238324	Promotion for Prime Field
42	21	11	Approved	2024-11-19 10:52:15.996372	Promotion for Olympus Court
43	27	11	Approved	2024-11-19 10:52:16.883719	Promotion for Pioneer Grounds
44	25	11	Approved	2024-11-19 10:52:18.310206	Promotion for Royal Arena
57	31	11	Approved	2024-11-19 10:59:56.609755	Promotion for Victory Fields
58	33	11	Approved	2024-11-19 10:59:57.36899	Promotion for Legend Court
59	11	11	Approved	2024-11-19 10:59:58.141692	Promotion for Victory Grounds
60	23	11	Approved	2024-11-19 10:59:58.821199	Promotion for Emerald Park
45	2	12	Approved	2024-11-19 10:59:02.529616	Promotion for Victory Park
46	4	12	Approved	2024-11-19 10:59:03.195535	Promotion for Riverside Field
47	8	12	Approved	2024-11-19 10:59:04.051408	Promotion for Golden Meadow
48	10	12	Approved	2024-11-19 10:59:04.576552	Promotion for Eagle Eye Field
49	12	12	Approved	2024-11-19 10:59:05.244464	Promotion for Diamond Court
50	14	12	Approved	2024-11-19 10:59:05.930552	Promotion for Sunrise Park
51	10	12	Approved	2024-11-19 10:59:07.049837	Promotion for Eagle Eye Field
52	8	12	Approved	2024-11-19 10:59:07.672216	Promotion for Golden Meadow
53	6	12	Approved	2024-11-19 10:59:08.337677	Promotion for Ace Arena
54	4	12	Approved	2024-11-19 10:59:09.027816	Promotion for Riverside Field
55	2	12	Approved	2024-11-19 10:59:09.722723	Promotion for Victory Park
56	4	12	Approved	2024-11-19 10:59:10.39761	Promotion for Riverside Field
61	35	11	Approved	2024-11-19 12:11:44.537362	Promotion for Diamond Grounds
62	37	11	Approved	2024-11-20 03:34:55.661537	Promotion for Sunrise Court
63	37	11	Approved	2024-11-20 11:23:12.025593	Promotion for Sunrise Court
64	9	11	Approved	2024-11-20 11:23:18.571207	Promotion for Majestic Field
65	13	11	Approved	2024-11-20 11:23:34.539046	Promotion for Highland Arena
66	13	11	Approved	2024-11-20 11:23:36.867115	Promotion for Highland Arena
67	17	11	Approved	2024-11-20 11:23:54.529249	Promotion for Prime Field
68	1	11	Approved	2024-11-20 11:24:04.80557	Promotion for Sunset Arena
69	1	11	Approved	2024-11-20 11:24:08.019751	Promotion for Sunset Arena
70	1	11	Approved	2024-11-20 11:24:10.099838	Promotion for Sunset Arena
71	1	11	Approved	2024-11-20 11:24:12.070745	Promotion for Sunset Arena
72	1	11	Approved	2024-11-20 11:24:14.090928	Promotion for Sunset Arena
73	1	11	Approved	2024-11-20 11:24:15.910501	Promotion for Sunset Arena
74	1	11	Approved	2024-11-20 11:24:17.413811	Promotion for Sunset Arena
75	1	11	Approved	2024-11-20 11:24:19.250244	Promotion for Sunset Arena
76	1	11	Approved	2024-11-20 11:24:24.538761	Promotion for Sunset Arena
77	1	11	Approved	2024-11-20 11:24:27.432026	Promotion for Sunset Arena
78	1	11	Approved	2024-11-20 11:24:29.594718	Promotion for Sunset Arena
79	39	11	Approved	2024-11-21 11:06:40.655718	Promotion for Majestic Court
80	29	11	Approved	2024-11-21 11:07:23.778505	Promotion for Sunbeam Arena
81	3	11	Approved	2024-11-21 11:36:08.742239	Promotion for Thunder Court
82	21	11	Approved	2024-11-21 11:36:11.432304	Promotion for Olympus Court
83	27	11	Approved	2024-11-21 11:36:23.30117	Promotion for Pioneer Grounds
84	27	11	Pending	2024-11-21 11:46:04.392353	Promotion for Pioneer Grounds
85	27	11	Pending	2024-11-21 11:46:07.492548	Promotion for Pioneer Grounds
86	27	11	Pending	2024-11-21 11:46:09.536727	Promotion for Pioneer Grounds
87	27	11	Pending	2024-11-21 11:46:11.46932	Promotion for Pioneer Grounds
88	27	11	Pending	2024-11-21 11:46:16.751174	Promotion for Pioneer Grounds
89	27	11	Pending	2024-11-21 11:46:18.945279	Promotion for Pioneer Grounds
90	27	11	Pending	2024-11-21 11:46:22.037826	Promotion for Pioneer Grounds
91	27	11	Pending	2024-11-21 11:46:24.189153	Promotion for Pioneer Grounds
92	41	11	Pending	2024-11-23 19:49:28.786006	Promotion for Noble Arena
\.


--
-- Data for Name: receipts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.receipts (receipt_id, booking_id, user_id, ground_id, total_amount, issued_at) FROM stdin;
3	3	1	5	100.00	2024-11-19 06:00:40.584787
13	13	1	5	100.00	2024-11-20 04:37:57.76096
14	14	1	10	100.00	2024-11-20 04:37:57.76096
15	15	1	18	100.00	2024-11-20 04:37:57.76096
16	16	1	3	100.00	2024-11-20 04:37:57.76096
17	17	1	20	100.00	2024-11-20 04:37:57.76096
18	18	2	3	100.00	2024-11-20 04:37:57.76096
19	19	2	7	100.00	2024-11-20 04:37:57.76096
20	20	2	12	100.00	2024-11-20 04:37:57.76096
21	21	2	17	100.00	2024-11-20 04:37:57.76096
22	22	2	22	100.00	2024-11-20 04:37:57.76096
23	23	3	8	100.00	2024-11-20 04:37:57.76096
24	24	3	13	100.00	2024-11-20 04:37:57.76096
25	25	3	14	100.00	2024-11-20 04:37:57.76096
26	26	4	15	100.00	2024-11-20 04:37:57.76096
27	27	4	20	100.00	2024-11-20 04:37:57.76096
28	28	4	25	100.00	2024-11-20 04:37:57.76096
29	29	4	30	100.00	2024-11-20 04:37:57.76096
30	30	4	5	100.00	2024-11-20 04:37:57.76096
31	31	4	2	100.00	2024-11-20 04:37:57.76096
32	32	5	3	100.00	2024-11-20 04:37:57.76096
33	33	5	19	100.00	2024-11-20 04:37:57.76096
34	34	5	11	100.00	2024-11-20 04:37:57.76096
35	35	6	2	100.00	2024-11-20 04:37:57.76096
36	36	6	9	100.00	2024-11-20 04:37:57.76096
37	37	6	14	100.00	2024-11-20 04:37:57.76096
38	38	6	17	100.00	2024-11-20 04:37:57.76096
39	39	6	22	100.00	2024-11-20 04:37:57.76096
40	40	6	25	100.00	2024-11-20 04:37:57.76096
41	41	6	31	100.00	2024-11-20 04:37:57.76096
42	42	7	5	100.00	2024-11-20 04:37:57.76096
43	43	7	16	100.00	2024-11-20 04:37:57.76096
44	44	8	10	100.00	2024-11-20 04:37:57.76096
45	45	8	12	100.00	2024-11-20 04:37:57.76096
46	46	8	19	100.00	2024-11-20 04:37:57.76096
47	47	8	27	100.00	2024-11-20 04:37:57.76096
48	48	9	15	100.00	2024-11-20 04:37:57.76096
49	49	9	20	100.00	2024-11-20 04:37:57.76096
50	50	9	25	100.00	2024-11-20 04:37:57.76096
51	51	9	30	100.00	2024-11-20 04:37:57.76096
52	52	9	3	100.00	2024-11-20 04:37:57.76096
53	53	9	4	100.00	2024-11-20 04:37:57.76096
54	54	10	18	100.00	2024-11-20 04:37:57.76096
55	55	10	7	100.00	2024-11-20 04:37:57.76096
56	56	10	10	100.00	2024-11-20 04:37:57.76096
57	57	10	21	100.00	2024-11-20 04:37:57.76096
58	58	1	5	100.00	2024-11-20 04:45:46.683117
59	59	1	5	100.00	2024-11-20 04:48:50.198402
60	60	1	5	100.00	2024-11-20 04:50:34.550768
67	67	1	7	100.00	2024-11-20 06:35:36.129774
68	68	8	31	100.00	2024-11-20 06:43:58.184544
69	69	1	27	100.00	2024-11-20 06:53:21.026654
70	70	1	13	100.00	2024-11-20 10:50:23.828565
71	71	1	1	100.00	2024-11-20 11:26:01.485948
72	72	1	13	100.00	2024-11-21 11:04:11.552608
73	73	1	13	100.00	2024-11-21 11:16:23.591599
74	74	1	1	100.00	2024-11-21 11:27:41.924656
75	75	1	10	100.00	2024-11-21 11:33:01.868917
76	76	1	28	100.00	2024-11-21 11:44:22.805693
77	77	1	10	100.00	2024-11-23 19:47:46.937006
\.


--
-- Data for Name: tournaments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tournaments (tournament_id, tournament_name, sport_type, location, start_date, end_date, created_at) FROM stdin;
2	Football Championship	Football	Indirangar	2024-12-01	2024-12-05	2024-11-19 14:12:29.01911
3	Cricket Tournament	Cricket	Koramangala	2024-12-10	2024-12-15	2024-11-19 14:12:29.01911
4	Badminton Open	Badminton	Banashankari	2024-12-20	2024-12-22	2024-11-19 14:12:29.01911
5	Football League	Football	Indirangar	2024-12-05	2024-12-09	2024-11-19 14:12:29.01911
6	Cricket Invitational	Cricket	Koramangala	2024-12-15	2024-12-18	2024-11-19 14:12:29.01911
7	Badminton Championship	Badminton	Banashankari	2024-12-25	2024-12-30	2024-11-19 14:12:29.01911
8	Football Cup	Football	Koramangala	2024-12-02	2024-12-06	2024-11-19 14:12:29.01911
9	Cricket Open	Cricket	Indirangar	2024-12-08	2024-12-12	2024-11-19 14:12:29.01911
10	Badminton Tournament	Badminton	Koramangala	2024-12-18	2024-12-21	2024-11-19 14:12:29.01911
11	Football Invitational	Football	Banashankari	2024-12-10	2024-12-14	2024-11-19 14:12:29.01911
12	Cricket League	Cricket	Banashankari	2024-12-11	2024-12-14	2024-11-19 14:12:29.01911
13	Badminton Open Challenge	Badminton	Indirangar	2024-12-22	2024-12-25	2024-11-19 14:12:29.01911
14	Football Invitational Cup	Football	Koramangala	2024-12-07	2024-12-11	2024-11-19 14:12:29.01911
15	Cricket World Cup	Cricket	Banashankari	2024-12-23	2024-12-27	2024-11-19 14:12:29.01911
16	Badminton Masters	Badminton	Indirangar	2024-12-30	2024-12-31	2024-11-19 14:12:29.01911
17	Football Tournament	Football	Koramangala	2024-12-12	2024-12-16	2024-11-19 14:12:29.01911
18	Cricket Test Series	Cricket	Banashankari	2024-12-20	2024-12-23	2024-11-19 14:12:29.01911
19	Badminton Championship Cup	Badminton	Koramangala	2024-12-05	2024-12-09	2024-11-19 14:12:29.01911
20	Football Super League	Football	Indirangar	2024-12-08	2024-12-12	2024-11-19 14:12:29.01911
21	Cricket Invitational Challenge	Cricket	Indirangar	2024-12-18	2024-12-22	2024-11-19 14:12:29.01911
22	Badminton Championship Open	Badminton	Banashankari	2024-12-10	2024-12-13	2024-11-19 14:12:29.01911
23	Football Premier League	Football	Koramangala	2024-12-14	2024-12-17	2024-11-19 14:12:29.01911
24	Cricket Pro Series	Cricket	Koramangala	2024-12-25	2024-12-28	2024-11-19 14:12:29.01911
25	Badminton Pro Cup	Badminton	Indirangar	2024-12-11	2024-12-14	2024-11-19 14:12:29.01911
26	Football Battle	Football	Banashankari	2024-12-02	2024-12-04	2024-11-19 14:12:29.01911
27	Cricket Invitational Cup	Cricket	Koramangala	2024-12-28	2024-12-31	2024-11-19 14:12:29.01911
28	Badminton Showdown	Badminton	Indirangar	2024-12-04	2024-12-07	2024-11-19 14:12:29.01911
29	Football Open Tournament	Football	Koramangala	2024-12-21	2024-12-24	2024-11-19 14:12:29.01911
30	Cricket Premier Cup	Cricket	Banashankari	2024-12-16	2024-12-19	2024-11-19 14:12:29.01911
31	Badminton Clash	Badminton	Koramangala	2024-12-26	2024-12-29	2024-11-19 14:12:29.01911
\.


--
-- Data for Name: user_issues; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_issues (issue_id, user_id, issue_type, description, status, created_at, updated_at) FROM stdin;
1	1	\N	hi	Open	2024-11-20 11:14:29.007538	2024-11-20 11:14:29.007538
2	1	\N	hi my name is shashwat	Open	2024-11-21 11:17:51.062157	2024-11-21 11:17:51.062157
3	1	\N	wallet not working	Open	2024-11-23 19:48:53.733598	2024-11-23 19:48:53.733598
\.


--
-- Data for Name: user_tournaments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_tournaments (user_id, tournament_id, joined_at) FROM stdin;
1	23	2024-11-19 14:44:39.247002
10	23	2024-11-19 14:44:39.247002
9	8	2024-11-19 14:44:39.247002
4	25	2024-11-19 14:44:39.247002
1	22	2024-11-19 14:44:39.247002
7	31	2024-11-19 14:44:39.247002
9	3	2024-11-19 14:44:39.247002
5	4	2024-11-19 14:44:39.247002
9	18	2024-11-19 14:44:39.247002
6	9	2024-11-19 14:44:39.247002
7	5	2024-11-19 14:44:39.247002
7	8	2024-11-19 14:44:39.247002
6	3	2024-11-19 14:44:39.247002
9	17	2024-11-19 14:44:39.247002
10	5	2024-11-19 14:44:39.247002
6	21	2024-11-19 14:44:39.247002
7	27	2024-11-19 14:44:39.247002
9	11	2024-11-19 14:44:39.247002
8	14	2024-11-19 14:44:39.247002
10	10	2024-11-19 14:44:39.247002
4	18	2024-11-19 14:44:39.247002
2	7	2024-11-19 14:44:39.247002
1	29	2024-11-19 14:44:39.247002
3	9	2024-11-19 14:44:39.247002
2	29	2024-11-19 14:44:39.247002
8	30	2024-11-19 14:44:39.247002
9	26	2024-11-19 14:44:39.247002
8	7	2024-11-19 14:44:39.247002
2	28	2024-11-19 14:44:39.247002
4	15	2024-11-19 14:44:39.247002
6	17	2024-11-19 14:44:39.247002
7	15	2024-11-19 14:44:39.247002
6	23	2024-11-19 14:44:39.247002
1	27	2024-11-19 14:44:39.247002
6	25	2024-11-19 14:44:39.247002
10	24	2024-11-19 14:44:39.247002
1	5	2024-11-19 14:44:39.247002
5	26	2024-11-19 14:44:39.247002
8	21	2024-11-19 14:44:39.247002
3	7	2024-11-19 14:44:39.247002
8	15	2024-11-19 14:44:39.247002
7	9	2024-11-19 14:44:39.247002
4	11	2024-11-19 14:44:39.247002
2	6	2024-11-19 14:44:39.247002
5	5	2024-11-19 14:44:39.247002
10	17	2024-11-19 14:44:39.247002
1	2	2024-11-20 02:49:14.917108
1	20	2024-11-20 02:49:19.950341
1	16	2024-11-20 11:26:52.608405
1	21	2024-11-21 11:05:53.191112
1	28	2024-11-21 11:44:48.974352
1	18	2024-11-23 19:48:30.463402
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (user_id, name, email, password, phone_number, created_at, updated_at, user_type) FROM stdin;
1	Alice Johnson	alice@example.com	password123	1234567890	2024-11-18 20:58:54.6266	2024-11-18 20:58:54.6266	booking_user
2	Bob Smith	bob@example.com	password456	9876543210	2024-11-18 20:58:54.6266	2024-11-18 20:58:54.6266	booking_user
3	Carol Lee	carol@example.com	password789	4567891230	2024-11-18 20:58:54.6266	2024-11-18 20:58:54.6266	booking_user
4	Ethan Brown	ethan@example.com	ethan123	1122334455	2024-11-18 20:58:54.6266	2024-11-18 20:58:54.6266	booking_user
5	Sophia Davis	sophia@example.com	sophia456	9988776655	2024-11-18 20:58:54.6266	2024-11-18 20:58:54.6266	booking_user
6	Liam Wilson	liam@example.com	liam789	7788991122	2024-11-18 20:58:54.6266	2024-11-18 20:58:54.6266	booking_user
7	Olivia Martinez	olivia@example.com	olivia321	5566778899	2024-11-18 20:58:54.6266	2024-11-18 20:58:54.6266	booking_user
8	Noah Moore	noah@example.com	noah654	4433221100	2024-11-18 20:58:54.6266	2024-11-18 20:58:54.6266	booking_user
9	Ava Taylor	ava@example.com	ava987	3344556677	2024-11-18 20:58:54.6266	2024-11-18 20:58:54.6266	booking_user
10	Mia Anderson	mia@example.com	mia111	2233445566	2024-11-18 20:58:54.6266	2024-11-18 20:58:54.6266	booking_user
11	David Parker	david@example.com	securepass1	5678901234	2024-11-18 20:58:54.6266	2024-11-18 20:58:54.6266	ground_owner
12	Emma Watson	emma@example.com	securepass2	6789012345	2024-11-18 20:58:54.6266	2024-11-18 20:58:54.6266	ground_owner
13	Super Admin	admin@example.com	supersecret	0000000000	2024-11-18 20:58:54.6266	2024-11-18 20:58:54.6266	superadmin
\.


--
-- Data for Name: wallet; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wallet (wallet_id, user_id, balance) FROM stdin;
12	12	4070.00
1	1	550.00
6	6	700.00
11	11	790.00
9	9	700.00
8	8	600.00
4	4	700.00
2	2	700.00
10	10	700.00
7	7	700.00
5	5	700.00
3	3	700.00
13	13	498580.00
\.


--
-- Data for Name: wallet_transactions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wallet_transactions (transaction_id, wallet_id, transaction_type, amount, transaction_date, description) FROM stdin;
3	1	debit	100.00	2024-11-19 06:00:40.584787	Booking payment for ground ID 5 on 2024-11-20 for Morning
7	11	debit	100.00	2024-11-19 10:19:48.937312	Deducted for pending promotion
8	11	debit	100.00	2024-11-19 10:19:48.937312	Deducted for pending promotion
9	11	debit	100.00	2024-11-19 10:19:48.937312	Deducted for pending promotion
10	11	debit	100.00	2024-11-19 10:19:48.937312	Deducted for pending promotion
11	11	debit	100.00	2024-11-19 10:19:48.937312	Deducted for pending promotion
12	11	debit	100.00	2024-11-19 10:19:48.937312	Deducted for pending promotion
13	11	debit	100.00	2024-11-19 10:19:48.937312	Deducted for pending promotion
14	11	debit	100.00	2024-11-19 10:19:48.937312	Deducted for pending promotion
15	11	debit	100.00	2024-11-19 10:19:48.937312	Deducted for pending promotion
16	11	debit	100.00	2024-11-19 10:19:48.937312	Deducted for pending promotion
17	11	debit	100.00	2024-11-19 10:19:48.937312	Deducted for pending promotion
18	11	debit	100.00	2024-11-19 10:47:38.358238	Deducted for pending promotion
19	11	debit	100.00	2024-11-19 10:47:38.358238	Deducted for pending promotion
20	11	debit	100.00	2024-11-19 10:47:38.358238	Deducted for pending promotion
21	11	debit	100.00	2024-11-19 10:47:38.358238	Deducted for pending promotion
22	11	debit	100.00	2024-11-19 10:47:38.358238	Deducted for pending promotion
23	11	debit	100.00	2024-11-19 10:47:38.358238	Deducted for pending promotion
24	11	debit	100.00	2024-11-19 10:47:38.358238	Deducted for pending promotion
25	11	debit	100.00	2024-11-19 10:53:01.31102	Deducted for pending promotion
26	11	debit	100.00	2024-11-19 10:53:01.31102	Deducted for pending promotion
27	11	debit	100.00	2024-11-19 10:53:01.31102	Deducted for pending promotion
28	11	debit	100.00	2024-11-19 10:53:01.31102	Deducted for pending promotion
29	11	debit	100.00	2024-11-19 10:53:01.31102	Deducted for pending promotion
30	11	debit	100.00	2024-11-19 10:53:01.31102	Deducted for pending promotion
31	11	debit	100.00	2024-11-19 10:53:01.31102	Deducted for pending promotion
32	11	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
33	11	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
34	11	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
35	11	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
36	12	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
37	12	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
38	12	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
39	12	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
40	12	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
41	12	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
42	12	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
43	12	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
44	12	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
45	12	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
46	12	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
47	12	debit	100.00	2024-11-19 11:00:31.953628	Deducted for pending promotion
48	11	debit	100.00	2024-11-19 12:14:20.010003	Deducted for pending promotion
53	1	credit	100.00	2024-11-20 03:57:10.129824	Added money to wallet.
54	1	credit	100.00	2024-11-20 03:57:13.562982	Added money to wallet.
55	1	credit	100.00	2024-11-20 03:57:17.252011	Added money to wallet.
56	1	credit	100.00	2024-11-20 03:57:18.882307	Added money to wallet.
60	1	debit	100.00	2024-11-20 04:45:46.683117	Booking payment for ground ID 5 on 2024-11-20 for Morning
61	11	credit	90.00	2024-11-20 04:45:46.683117	Booking payment for ground ID 5 on 2024-11-20 for Morning
62	1	debit	100.00	2024-11-20 04:48:50.198402	Booking payment for ground ID 5 on 2024-11-20 for Morning
63	11	credit	90.00	2024-11-20 04:48:50.198402	Booking payment for ground ID 5 on 2024-11-20 for Morning
64	1	debit	100.00	2024-11-20 04:50:34.550768	Booking payment for ground ID 5 on 2024-11-20 for Morning
65	11	credit	90.00	2024-11-20 04:50:34.550768	Booking payment for ground ID 5 on 2024-11-20 for Morning
78	1	credit	100.00	2024-11-20 06:28:59.845821	Added money to wallet.
79	1	credit	100.00	2024-11-20 06:29:05.929131	Added money to wallet.
80	1	debit	100.00	2024-11-20 06:35:36.129774	Booking payment for ground ID 7 on 2024-11-21 for Early Morning
81	11	credit	90.00	2024-11-20 06:35:36.129774	Booking payment for ground ID 7 on 2024-11-21 for Early Morning
82	8	debit	100.00	2024-11-20 06:43:58.184544	Booking payment for ground ID 31 on 2024-11-21 for Early Morning
83	11	credit	90.00	2024-11-20 06:43:58.184544	Booking payment for ground ID 31 on 2024-11-21 for Early Morning
84	1	debit	100.00	2024-11-20 06:53:21.026654	Booking payment for ground ID 27 on 2024-11-21 for Evening
85	11	credit	90.00	2024-11-20 06:53:21.026654	Booking payment for ground ID 27 on 2024-11-21 for Evening
86	1	debit	100.00	2024-11-20 10:50:23.828565	Booking payment for ground ID 13 on 2024-11-21 for Early Morning
87	11	credit	90.00	2024-11-20 10:50:23.828565	Booking payment for ground ID 13 on 2024-11-21 for Early Morning
88	1	credit	100.00	2024-11-20 11:00:08.305269	Added money to wallet.
89	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
90	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
91	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
92	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
93	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
94	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
95	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
96	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
97	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
98	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
99	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
100	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
101	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
102	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
103	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
104	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
105	11	debit	100.00	2024-11-20 11:24:55.475576	Deducted for pending promotion
106	1	debit	100.00	2024-11-20 11:26:01.485948	Booking payment for ground ID 1 on 2024-11-21 for Afternoon
107	11	credit	90.00	2024-11-20 11:26:01.485948	Booking payment for ground ID 1 on 2024-11-21 for Afternoon
108	1	debit	100.00	2024-11-21 11:04:11.552608	Booking payment for ground ID 13 on 2024-11-21 for Midnight
109	11	credit	90.00	2024-11-21 11:04:11.552608	Booking payment for ground ID 13 on 2024-11-21 for Midnight
110	1	credit	100.00	2024-11-21 11:05:29.234244	Added money to wallet.
111	11	debit	100.00	2024-11-21 11:09:02.102616	Deducted for pending promotion
112	11	debit	100.00	2024-11-21 11:09:02.102616	Deducted for pending promotion
113	1	debit	100.00	2024-11-21 11:16:23.591599	Booking payment for ground ID 13 on 2024-11-21 for Evening
114	11	credit	90.00	2024-11-21 11:16:23.591599	Booking payment for ground ID 13 on 2024-11-21 for Evening
115	1	credit	100.00	2024-11-21 11:19:12.082518	Added money to wallet.
116	1	debit	100.00	2024-11-21 11:27:41.924656	Booking payment for ground ID 1 on 2024-11-21 for Night
117	11	credit	90.00	2024-11-21 11:27:41.924656	Booking payment for ground ID 1 on 2024-11-21 for Night
118	1	credit	100.00	2024-11-21 11:32:08.641263	Added money to wallet.
119	1	debit	100.00	2024-11-21 11:33:01.868917	Booking payment for ground ID 10 on 2024-11-21 for Afternoon
120	12	credit	90.00	2024-11-21 11:33:01.868917	Booking payment for ground ID 10 on 2024-11-21 for Afternoon
121	11	debit	100.00	2024-11-21 11:36:59.570186	Deducted for pending promotion
122	11	debit	100.00	2024-11-21 11:36:59.570186	Deducted for pending promotion
123	11	debit	100.00	2024-11-21 11:36:59.570186	Deducted for pending promotion
124	1	debit	100.00	2024-11-21 11:44:22.805693	Booking payment for ground ID 28 on 2024-11-21 for Midnight
125	12	credit	90.00	2024-11-21 11:44:22.805693	Booking payment for ground ID 28 on 2024-11-21 for Midnight
126	1	credit	100.00	2024-11-21 11:44:36.562127	Added money to wallet.
134	1	debit	100.00	2024-11-23 19:47:46.937006	Booking payment for ground ID 10 on 2024-11-21 for Night
135	12	credit	90.00	2024-11-23 19:47:46.937006	Booking payment for ground ID 10 on 2024-11-21 for Night
136	1	credit	100.00	2024-11-23 19:48:34.865149	Added money to wallet.
\.


--
-- Name: availability_availability_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.availability_availability_id_seq', 1722, true);


--
-- Name: bookings_booking_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.bookings_booking_id_seq', 77, true);


--
-- Name: grounds_ground_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.grounds_ground_id_seq', 41, true);


--
-- Name: promotions_promotion_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.promotions_promotion_id_seq', 92, true);


--
-- Name: receipts_receipt_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.receipts_receipt_id_seq', 77, true);


--
-- Name: tournaments_tournament_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tournaments_tournament_id_seq', 31, true);


--
-- Name: user_issues_issue_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.user_issues_issue_id_seq', 3, true);


--
-- Name: users_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_user_id_seq', 13, true);


--
-- Name: wallet_transactions_transaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wallet_transactions_transaction_id_seq', 143, true);


--
-- Name: wallet_wallet_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wallet_wallet_id_seq', 13, true);


--
-- Name: availability availability_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.availability
    ADD CONSTRAINT availability_pkey PRIMARY KEY (availability_id);


--
-- Name: bookings bookings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_pkey PRIMARY KEY (booking_id);


--
-- Name: grounds grounds_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grounds
    ADD CONSTRAINT grounds_pkey PRIMARY KEY (ground_id);


--
-- Name: promotions promotions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_pkey PRIMARY KEY (promotion_id);


--
-- Name: receipts receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.receipts
    ADD CONSTRAINT receipts_pkey PRIMARY KEY (receipt_id);


--
-- Name: tournaments tournaments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tournaments
    ADD CONSTRAINT tournaments_pkey PRIMARY KEY (tournament_id);


--
-- Name: user_issues user_issues_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_issues
    ADD CONSTRAINT user_issues_pkey PRIMARY KEY (issue_id);


--
-- Name: user_tournaments user_tournaments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_tournaments
    ADD CONSTRAINT user_tournaments_pkey PRIMARY KEY (user_id, tournament_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: wallet wallet_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet
    ADD CONSTRAINT wallet_pkey PRIMARY KEY (wallet_id);


--
-- Name: wallet_transactions wallet_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_pkey PRIMARY KEY (transaction_id);


--
-- Name: wallet wallet_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet
    ADD CONSTRAINT wallet_user_id_key UNIQUE (user_id);


--
-- Name: bookings after_booking_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER after_booking_insert AFTER INSERT ON public.bookings FOR EACH ROW EXECUTE FUNCTION public.generate_receipt();


--
-- Name: availability availability_ground_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.availability
    ADD CONSTRAINT availability_ground_id_fkey FOREIGN KEY (ground_id) REFERENCES public.grounds(ground_id) ON DELETE CASCADE;


--
-- Name: bookings bookings_ground_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_ground_id_fkey FOREIGN KEY (ground_id) REFERENCES public.grounds(ground_id) ON DELETE CASCADE;


--
-- Name: grounds grounds_creator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.grounds
    ADD CONSTRAINT grounds_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: promotions promotions_creator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_creator_id_fkey FOREIGN KEY (creator_id) REFERENCES public.users(user_id) ON DELETE SET NULL;


--
-- Name: promotions promotions_ground_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_ground_id_fkey FOREIGN KEY (ground_id) REFERENCES public.grounds(ground_id) ON DELETE CASCADE;


--
-- Name: receipts receipts_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.receipts
    ADD CONSTRAINT receipts_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(booking_id);


--
-- Name: receipts receipts_ground_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.receipts
    ADD CONSTRAINT receipts_ground_id_fkey FOREIGN KEY (ground_id) REFERENCES public.grounds(ground_id);


--
-- Name: receipts receipts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.receipts
    ADD CONSTRAINT receipts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: user_issues user_issues_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_issues
    ADD CONSTRAINT user_issues_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id);


--
-- Name: user_tournaments user_tournaments_tournament_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_tournaments
    ADD CONSTRAINT user_tournaments_tournament_id_fkey FOREIGN KEY (tournament_id) REFERENCES public.tournaments(tournament_id) ON DELETE CASCADE;


--
-- Name: user_tournaments user_tournaments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_tournaments
    ADD CONSTRAINT user_tournaments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: wallet_transactions wallet_transactions_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallet(wallet_id) ON DELETE CASCADE;


--
-- Name: wallet wallet_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet
    ADD CONSTRAINT wallet_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON DELETE CASCADE;


--
-- Name: TABLE availability; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.availability TO super_admin;


--
-- Name: TABLE bookings; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.bookings TO super_admin;
GRANT SELECT ON TABLE public.bookings TO ground_owner;
GRANT SELECT ON TABLE public.bookings TO booking_user;


--
-- Name: TABLE grounds; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.grounds TO super_admin;
GRANT ALL ON TABLE public.grounds TO ground_owner;
GRANT SELECT ON TABLE public.grounds TO booking_user;


--
-- Name: TABLE promotions; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.promotions TO super_admin;


--
-- Name: TABLE receipts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.receipts TO super_admin;
GRANT SELECT ON TABLE public.receipts TO booking_user;


--
-- Name: TABLE tournaments; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.tournaments TO super_admin;
GRANT SELECT ON TABLE public.tournaments TO booking_user;


--
-- Name: TABLE user_issues; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_issues TO super_admin;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.user_issues TO customer_support;


--
-- Name: TABLE user_tournaments; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT ON TABLE public.user_tournaments TO booking_user;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.users TO super_admin;


--
-- Name: TABLE wallet; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wallet TO super_admin;
GRANT UPDATE ON TABLE public.wallet TO ground_owner;
GRANT UPDATE ON TABLE public.wallet TO booking_user;


--
-- Name: TABLE wallet_transactions; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wallet_transactions TO super_admin;
GRANT SELECT ON TABLE public.wallet_transactions TO ground_owner;


--
-- PostgreSQL database dump complete
--

