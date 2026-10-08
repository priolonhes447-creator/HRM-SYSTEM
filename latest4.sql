--
-- PostgreSQL database dump
--

\restrict MtvT7NavICG68QLTUMcajCAd9M6XL79jWvt6OG8vW46o9Hi1wpxOHwUKAhE86zJ

-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11

-- Started on 2026-10-08 04:41:26

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
-- TOC entry 245 (class 1255 OID 24843)
-- Name: enforce_unique_person_name(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.enforce_unique_person_name() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    normalized_name TEXT;
BEGIN
    normalized_name := LOWER(REGEXP_REPLACE(BTRIM(COALESCE(NEW.name, '')), '[[:space:]]+', ' ', 'g'));
    IF normalized_name = '' THEN
        RETURN NEW;
    END IF;

    PERFORM pg_advisory_xact_lock(19789, 1);

    IF TG_TABLE_NAME = 'employees' THEN
        IF EXISTS (
            SELECT 1
            FROM public.employees existing
            WHERE existing.id <> NEW.id
              AND LOWER(REGEXP_REPLACE(BTRIM(COALESCE(existing.name, '')), '[[:space:]]+', ' ', 'g')) = normalized_name
        ) OR EXISTS (
            SELECT 1
            FROM public.applicants existing
            WHERE LOWER(REGEXP_REPLACE(BTRIM(COALESCE(existing.name, '')), '[[:space:]]+', ' ', 'g')) = normalized_name
              AND NOT (
                  existing.status = 'Hired'
                  AND NULLIF(BTRIM(COALESCE(existing.email, '')), '') IS NOT NULL
                  AND LOWER(BTRIM(existing.email)) = LOWER(BTRIM(COALESCE(NEW.email, '')))
              )
        ) THEN
            RAISE EXCEPTION 'DUPLICATE_PERSON_NAME: A person with this full name already exists in Employee or Applicant records.'
                USING ERRCODE = '23505', CONSTRAINT = 'people_name_unique';
        END IF;
    ELSE
        IF EXISTS (
            SELECT 1
            FROM public.applicants existing
            WHERE existing.id <> NEW.id
              AND LOWER(REGEXP_REPLACE(BTRIM(COALESCE(existing.name, '')), '[[:space:]]+', ' ', 'g')) = normalized_name
        ) OR EXISTS (
            SELECT 1
            FROM public.employees existing
            WHERE LOWER(REGEXP_REPLACE(BTRIM(COALESCE(existing.name, '')), '[[:space:]]+', ' ', 'g')) = normalized_name
              AND NOT (
                  NEW.status = 'Hired'
                  AND NULLIF(BTRIM(COALESCE(NEW.email, '')), '') IS NOT NULL
                  AND LOWER(BTRIM(existing.email)) = LOWER(BTRIM(NEW.email))
              )
        ) THEN
            RAISE EXCEPTION 'DUPLICATE_PERSON_NAME: A person with this full name already exists in Employee or Applicant records.'
                USING ERRCODE = '23505', CONSTRAINT = 'people_name_unique';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.enforce_unique_person_name() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 226 (class 1259 OID 16465)
-- Name: announcement_reads; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.announcement_reads (
    id integer NOT NULL,
    user_id integer NOT NULL,
    announcement_id integer NOT NULL,
    read_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.announcement_reads OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 16464)
-- Name: announcement_reads_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.announcement_reads_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.announcement_reads_id_seq OWNER TO postgres;

--
-- TOC entry 5072 (class 0 OID 0)
-- Dependencies: 225
-- Name: announcement_reads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.announcement_reads_id_seq OWNED BY public.announcement_reads.id;


--
-- TOC entry 224 (class 1259 OID 16454)
-- Name: announcements; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.announcements (
    id integer NOT NULL,
    title character varying(255) NOT NULL,
    content text NOT NULL,
    author character varying(100) DEFAULT 'HR'::character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.announcements OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 16453)
-- Name: announcements_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.announcements_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.announcements_id_seq OWNER TO postgres;

--
-- TOC entry 5073 (class 0 OID 0)
-- Dependencies: 223
-- Name: announcements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.announcements_id_seq OWNED BY public.announcements.id;


--
-- TOC entry 222 (class 1259 OID 16437)
-- Name: applicants; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.applicants (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    surname character varying(100) DEFAULT ''::character varying,
    middle_name character varying(100) DEFAULT ''::character varying,
    first_name character varying(100) DEFAULT ''::character varying,
    "position" character varying(100),
    email character varying(100) DEFAULT ''::character varying,
    phone character varying(50) DEFAULT ''::character varying,
    applied_date character varying(20) NOT NULL,
    status character varying(20) DEFAULT 'New'::character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    department character varying(100) DEFAULT 'General'::character varying,
    gender character varying(20) DEFAULT ''::character varying,
    address text DEFAULT ''::text,
    date_of_birth character varying(20) DEFAULT ''::character varying,
    age integer DEFAULT 0,
    place_of_birth character varying(100) DEFAULT ''::character varying,
    tin character varying(50) DEFAULT ''::character varying,
    civil_status character varying(20) DEFAULT ''::character varying,
    emergency_contact character varying(150) DEFAULT ''::character varying,
    emergency_contact_name character varying(100) DEFAULT ''::character varying,
    emergency_contact_phone character varying(50) DEFAULT ''::character varying,
    id_photo_path character varying(100) DEFAULT ''::character varying,
    id_picture_path character varying(100) DEFAULT ''::character varying,
    resume_path character varying(100) DEFAULT ''::character varying,
    comments text DEFAULT ''::text,
    sss_number character varying(50) DEFAULT ''::character varying,
    pag_ibig_number character varying(50) DEFAULT ''::character varying,
    nbi_number character varying(50) DEFAULT ''::character varying,
    sss_photo_path character varying(100) DEFAULT ''::character varying,
    pag_ibig_photo_path character varying(100) DEFAULT ''::character varying,
    nbi_photo_path character varying(100) DEFAULT ''::character varying,
    health_card_photo_path character varying(100) DEFAULT ''::character varying,
    psa_photo_path character varying(100) DEFAULT ''::character varying,
    CONSTRAINT applicants_status_check CHECK (((status)::text = ANY ((ARRAY['New'::character varying, 'Interviewing'::character varying, 'Hired'::character varying, 'Rejected'::character varying])::text[])))
);


ALTER TABLE public.applicants OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 16436)
-- Name: applicants_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.applicants_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.applicants_id_seq OWNER TO postgres;

--
-- TOC entry 5074 (class 0 OID 0)
-- Dependencies: 221
-- Name: applicants_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.applicants_id_seq OWNED BY public.applicants.id;


--
-- TOC entry 234 (class 1259 OID 16557)
-- Name: attendance; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.attendance (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    employee_id character varying(50) DEFAULT ''::character varying,
    date character varying(20) NOT NULL,
    clock_in character varying(30) DEFAULT ''::character varying,
    clock_out character varying(30) DEFAULT ''::character varying,
    status character varying(20) DEFAULT 'Present'::character varying,
    notes text DEFAULT ''::text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.attendance OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 16556)
-- Name: attendance_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.attendance_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.attendance_id_seq OWNER TO postgres;

--
-- TOC entry 5075 (class 0 OID 0)
-- Dependencies: 233
-- Name: attendance_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.attendance_id_seq OWNED BY public.attendance.id;


--
-- TOC entry 238 (class 1259 OID 16596)
-- Name: employee_documents; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.employee_documents (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    employee_id character varying(50) DEFAULT ''::character varying,
    doc_type character varying(100) NOT NULL,
    title character varying(255) NOT NULL,
    description text DEFAULT ''::text,
    status character varying(20) DEFAULT 'Available'::character varying,
    file_url text DEFAULT ''::text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.employee_documents OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 16595)
-- Name: employee_documents_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.employee_documents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employee_documents_id_seq OWNER TO postgres;

--
-- TOC entry 5076 (class 0 OID 0)
-- Dependencies: 237
-- Name: employee_documents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.employee_documents_id_seq OWNED BY public.employee_documents.id;


--
-- TOC entry 220 (class 1259 OID 16407)
-- Name: employees; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.employees (
    id integer NOT NULL,
    employee_id character varying(50) NOT NULL,
    name character varying(100) NOT NULL,
    email character varying(100) NOT NULL,
    department character varying(100) DEFAULT 'General'::character varying,
    role character varying(100) DEFAULT ''::character varying,
    status character varying(20) DEFAULT 'Active'::character varying,
    phone character varying(50) DEFAULT ''::character varying,
    address text DEFAULT ''::text,
    date_of_birth character varying(20) DEFAULT ''::character varying,
    gender character varying(20) DEFAULT ''::character varying,
    emergency_contact character varying(150) DEFAULT ''::character varying,
    age integer DEFAULT 0,
    place_of_birth character varying(100) DEFAULT ''::character varying,
    tin character varying(50) DEFAULT ''::character varying,
    civil_status character varying(20) DEFAULT ''::character varying,
    last_name character varying(50) DEFAULT ''::character varying,
    first_name character varying(50) DEFAULT ''::character varying,
    middle_name character varying(50) DEFAULT ''::character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    bank_name character varying(100) DEFAULT ''::character varying,
    bank_account character varying(100) DEFAULT ''::character varying,
    sss_number character varying(50) DEFAULT ''::character varying,
    pag_ibig_number character varying(50) DEFAULT ''::character varying,
    nbi_number character varying(50) DEFAULT ''::character varying,
    emergency_contact_name character varying(100) DEFAULT ''::character varying,
    emergency_contact_phone character varying(50) DEFAULT ''::character varying,
    id_photo_path character varying(100) DEFAULT ''::character varying,
    id_picture_path character varying(100) DEFAULT ''::character varying,
    resume_path character varying(100) DEFAULT ''::character varying,
    sss_photo_path character varying(100) DEFAULT ''::character varying,
    pag_ibig_photo_path character varying(100) DEFAULT ''::character varying,
    nbi_photo_path character varying(100) DEFAULT ''::character varying,
    health_card_photo_path character varying(100) DEFAULT ''::character varying,
    psa_photo_path character varying(100) DEFAULT ''::character varying,
    applied_date character varying(20) DEFAULT ''::character varying,
    archived_at timestamp with time zone,
    archived_by bigint,
    comments text DEFAULT ''::text,
    certificate_received_at timestamp with time zone,
    contract_signed_photo_path character varying(100) DEFAULT ''::character varying,
    CONSTRAINT employees_status_check CHECK (((status)::text = ANY ((ARRAY['Active'::character varying, 'On Leave'::character varying, 'Onboarding'::character varying, 'Inactive'::character varying, 'Complete'::character varying, 'Unhired'::character varying])::text[])))
);


ALTER TABLE public.employees OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 16406)
-- Name: employees_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.employees_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employees_id_seq OWNER TO postgres;

--
-- TOC entry 5077 (class 0 OID 0)
-- Dependencies: 219
-- Name: employees_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.employees_id_seq OWNED BY public.employees.id;


--
-- TOC entry 240 (class 1259 OID 16622)
-- Name: interviews; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.interviews (
    id bigint NOT NULL,
    applicant_id integer NOT NULL,
    scheduled_at timestamp without time zone NOT NULL,
    interviewer character varying(100) NOT NULL,
    interview_type character varying(30) DEFAULT 'In person'::character varying NOT NULL,
    location text DEFAULT ''::text,
    notes text DEFAULT ''::text,
    status character varying(50) DEFAULT 'Scheduled'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT interviews_interview_type_check CHECK (((interview_type)::text = ANY ((ARRAY['In person'::character varying, 'Video'::character varying, 'Phone'::character varying])::text[]))),
    CONSTRAINT interviews_status_check CHECK (((status)::text = ANY ((ARRAY['Scheduled'::character varying, 'Completed'::character varying, 'Cancelled'::character varying, 'No Show'::character varying, 'Did Not Pass the Interview'::character varying])::text[])))
);


ALTER TABLE public.interviews OWNER TO postgres;

--
-- TOC entry 239 (class 1259 OID 16621)
-- Name: interviews_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.interviews_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.interviews_id_seq OWNER TO postgres;

--
-- TOC entry 5078 (class 0 OID 0)
-- Dependencies: 239
-- Name: interviews_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.interviews_id_seq OWNED BY public.interviews.id;


--
-- TOC entry 232 (class 1259 OID 16537)
-- Name: leave_requests; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.leave_requests (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    employee_id character varying(50) DEFAULT ''::character varying,
    leave_type character varying(20) NOT NULL,
    start_date character varying(20) NOT NULL,
    end_date character varying(20) NOT NULL,
    days_count integer DEFAULT 1,
    reason text DEFAULT ''::text,
    status character varying(20) DEFAULT 'Pending'::character varying,
    admin_remarks text DEFAULT ''::text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.leave_requests OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 16536)
-- Name: leave_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.leave_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.leave_requests_id_seq OWNER TO postgres;

--
-- TOC entry 5079 (class 0 OID 0)
-- Dependencies: 231
-- Name: leave_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.leave_requests_id_seq OWNED BY public.leave_requests.id;


--
-- TOC entry 244 (class 1259 OID 24873)
-- Name: login_verifications; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.login_verifications (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    challenge_hash character(64) NOT NULL,
    otp_hash character varying(255) NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.login_verifications OWNER TO postgres;

--
-- TOC entry 243 (class 1259 OID 24872)
-- Name: login_verifications_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.login_verifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.login_verifications_id_seq OWNER TO postgres;

--
-- TOC entry 5080 (class 0 OID 0)
-- Dependencies: 243
-- Name: login_verifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.login_verifications_id_seq OWNED BY public.login_verifications.id;


--
-- TOC entry 228 (class 1259 OID 16485)
-- Name: onboarding_tasks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.onboarding_tasks (
    id integer NOT NULL,
    employee_id integer NOT NULL,
    task character varying(255) NOT NULL,
    status character varying(20) DEFAULT 'Pending'::character varying,
    due_date character varying(20) DEFAULT ''::character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT onboarding_tasks_status_check CHECK (((status)::text = ANY ((ARRAY['Pending'::character varying, 'In Progress'::character varying, 'Completed'::character varying])::text[])))
);


ALTER TABLE public.onboarding_tasks OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 16484)
-- Name: onboarding_tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.onboarding_tasks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.onboarding_tasks_id_seq OWNER TO postgres;

--
-- TOC entry 5081 (class 0 OID 0)
-- Dependencies: 227
-- Name: onboarding_tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.onboarding_tasks_id_seq OWNED BY public.onboarding_tasks.id;


--
-- TOC entry 230 (class 1259 OID 16518)
-- Name: password_resets; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.password_resets (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    otp_hash character varying(255) NOT NULL,
    reset_token_hash character varying(255),
    expires_at timestamp with time zone NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    verified_at timestamp with time zone,
    used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.password_resets OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 16512)
-- Name: password_resets_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.password_resets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.password_resets_id_seq OWNER TO postgres;

--
-- TOC entry 5082 (class 0 OID 0)
-- Dependencies: 229
-- Name: password_resets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.password_resets_id_seq OWNED BY public.password_resets.id;


--
-- TOC entry 236 (class 1259 OID 16577)
-- Name: payslips; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.payslips (
    id bigint NOT NULL,
    user_id integer NOT NULL,
    employee_id character varying(50) DEFAULT ''::character varying,
    pay_period character varying(100) NOT NULL,
    pay_date character varying(20) NOT NULL,
    basic_salary numeric(12,2) DEFAULT 0,
    allowances numeric(12,2) DEFAULT 0,
    deductions numeric(12,2) DEFAULT 0,
    net_pay numeric(12,2) DEFAULT 0,
    status character varying(20) DEFAULT 'Paid'::character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.payslips OWNER TO postgres;

--
-- TOC entry 235 (class 1259 OID 16576)
-- Name: payslips_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.payslips_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.payslips_id_seq OWNER TO postgres;

--
-- TOC entry 5083 (class 0 OID 0)
-- Dependencies: 235
-- Name: payslips_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.payslips_id_seq OWNED BY public.payslips.id;


--
-- TOC entry 242 (class 1259 OID 24831)
-- Name: system_activities; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.system_activities (
    id bigint NOT NULL,
    actor_id bigint,
    actor_name character varying(150) NOT NULL,
    actor_role character varying(50) DEFAULT ''::character varying,
    activity character varying(255) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.system_activities OWNER TO postgres;

--
-- TOC entry 241 (class 1259 OID 24830)
-- Name: system_activities_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.system_activities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.system_activities_id_seq OWNER TO postgres;

--
-- TOC entry 5084 (class 0 OID 0)
-- Dependencies: 241
-- Name: system_activities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.system_activities_id_seq OWNED BY public.system_activities.id;


--
-- TOC entry 218 (class 1259 OID 16389)
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id integer NOT NULL,
    email character varying(100) NOT NULL,
    password character varying(255) NOT NULL,
    role character varying(20) DEFAULT 'employee'::character varying NOT NULL,
    name character varying(100) NOT NULL,
    "position" character varying(100) DEFAULT ''::character varying,
    department character varying(100) DEFAULT ''::character varying,
    employee_id character varying(50),
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT users_role_check CHECK (((role)::text = ANY ((ARRAY['admin'::character varying, 'hr'::character varying, 'employee'::character varying])::text[])))
);


ALTER TABLE public.users OWNER TO postgres;

--
-- TOC entry 217 (class 1259 OID 16388)
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNER TO postgres;

--
-- TOC entry 5085 (class 0 OID 0)
-- Dependencies: 217
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- TOC entry 4781 (class 2604 OID 16468)
-- Name: announcement_reads id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcement_reads ALTER COLUMN id SET DEFAULT nextval('public.announcement_reads_id_seq'::regclass);


--
-- TOC entry 4778 (class 2604 OID 16457)
-- Name: announcements id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcements ALTER COLUMN id SET DEFAULT nextval('public.announcements_id_seq'::regclass);


--
-- TOC entry 4747 (class 2604 OID 16440)
-- Name: applicants id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.applicants ALTER COLUMN id SET DEFAULT nextval('public.applicants_id_seq'::regclass);


--
-- TOC entry 4797 (class 2604 OID 16560)
-- Name: attendance id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance ALTER COLUMN id SET DEFAULT nextval('public.attendance_id_seq'::regclass);


--
-- TOC entry 4812 (class 2604 OID 16599)
-- Name: employee_documents id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee_documents ALTER COLUMN id SET DEFAULT nextval('public.employee_documents_id_seq'::regclass);


--
-- TOC entry 4712 (class 2604 OID 16410)
-- Name: employees id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees ALTER COLUMN id SET DEFAULT nextval('public.employees_id_seq'::regclass);


--
-- TOC entry 4818 (class 2604 OID 16625)
-- Name: interviews id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interviews ALTER COLUMN id SET DEFAULT nextval('public.interviews_id_seq'::regclass);


--
-- TOC entry 4790 (class 2604 OID 16540)
-- Name: leave_requests id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leave_requests ALTER COLUMN id SET DEFAULT nextval('public.leave_requests_id_seq'::regclass);


--
-- TOC entry 4827 (class 2604 OID 24876)
-- Name: login_verifications id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.login_verifications ALTER COLUMN id SET DEFAULT nextval('public.login_verifications_id_seq'::regclass);


--
-- TOC entry 4783 (class 2604 OID 16488)
-- Name: onboarding_tasks id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.onboarding_tasks ALTER COLUMN id SET DEFAULT nextval('public.onboarding_tasks_id_seq'::regclass);


--
-- TOC entry 4787 (class 2604 OID 16523)
-- Name: password_resets id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.password_resets ALTER COLUMN id SET DEFAULT nextval('public.password_resets_id_seq'::regclass);


--
-- TOC entry 4804 (class 2604 OID 16580)
-- Name: payslips id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payslips ALTER COLUMN id SET DEFAULT nextval('public.payslips_id_seq'::regclass);


--
-- TOC entry 4824 (class 2604 OID 24834)
-- Name: system_activities id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_activities ALTER COLUMN id SET DEFAULT nextval('public.system_activities_id_seq'::regclass);


--
-- TOC entry 4707 (class 2604 OID 16392)
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- TOC entry 5048 (class 0 OID 16465)
-- Dependencies: 226
-- Data for Name: announcement_reads; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.announcement_reads (id, user_id, announcement_id, read_at) FROM stdin;
\.


--
-- TOC entry 5046 (class 0 OID 16454)
-- Dependencies: 224
-- Data for Name: announcements; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.announcements (id, title, content, author, created_at) FROM stdin;
3	Welcome to Our New Team Members	Please join us in welcoming the new hires joining the Engineering and Sales teams this month!	HR	2026-09-24 15:35:43.100574+08
1	Upcoming Town Hall Meeting	Join us this Friday at 3:00 PM for the quarterly review. Refreshments will be served!	Human Resources	2026-09-24 15:35:43.100574+08
2	New Office Hours	Effective next Monday, the office will open at 8:30 AM. Please adjust your schedules accordingly.	Human Resources	2026-09-24 15:35:43.100574+08
4	fgdgdfg	fdgfgfgdfgfdg	Admin	2026-10-07 11:01:20.392214+08
\.


--
-- TOC entry 5044 (class 0 OID 16437)
-- Dependencies: 222
-- Data for Name: applicants; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.applicants (id, name, surname, middle_name, first_name, "position", email, phone, applied_date, status, created_at, department, gender, address, date_of_birth, age, place_of_birth, tin, civil_status, emergency_contact, emergency_contact_name, emergency_contact_phone, id_photo_path, id_picture_path, resume_path, comments, sss_number, pag_ibig_number, nbi_number, sss_photo_path, pag_ibig_photo_path, nbi_photo_path, health_card_photo_path, psa_photo_path) FROM stdin;
21	Nhes Nicole Priolo	Priolo	Nicole	Nhes	Driver	nicole123mmmm@gmail.com	09289389283	2026-10-07	Hired	2026-10-07 21:35:22.278367+08	General	Male	243 Dama De Noche St	1996-06-07	30	QUEZOZ	4523542343	Single	Nhes Priolo - 0878657667	Nhes Priolo	0878657667	0c03bc9147f1d8ffdf53e2dc7e49f216.png	22e9f98ba7c6bc3b72d58d4b1046d845.png	089ce2b841ae66ef950f0cc67a6e433a.pdf		1231231	3432432434234	21321321321	f6c90fdfb9bc505bf508ea5b9b0d1d75.png	f97f2da7956b7276b8e6abba7974faae.png	\N	\N	\N
\.


--
-- TOC entry 5056 (class 0 OID 16557)
-- Dependencies: 234
-- Data for Name: attendance; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.attendance (id, user_id, employee_id, date, clock_in, clock_out, status, notes, created_at) FROM stdin;
\.


--
-- TOC entry 5060 (class 0 OID 16596)
-- Dependencies: 238
-- Data for Name: employee_documents; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.employee_documents (id, user_id, employee_id, doc_type, title, description, status, file_url, created_at) FROM stdin;
\.


--
-- TOC entry 5042 (class 0 OID 16407)
-- Dependencies: 220
-- Data for Name: employees; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.employees (id, employee_id, name, email, department, role, status, phone, address, date_of_birth, gender, emergency_contact, age, place_of_birth, tin, civil_status, last_name, first_name, middle_name, created_at, bank_name, bank_account, sss_number, pag_ibig_number, nbi_number, emergency_contact_name, emergency_contact_phone, id_photo_path, id_picture_path, resume_path, sss_photo_path, pag_ibig_photo_path, nbi_photo_path, health_card_photo_path, psa_photo_path, applied_date, archived_at, archived_by, comments, certificate_received_at, contract_signed_photo_path) FROM stdin;
23	EMP004	Nhes Nicole Priolo	nicole123mmmm@gmail.com	HR	Driver	Complete	09289389283	243 Dama De Noche St	1996-06-07	Male	Nhes Priolo - 0878657667	30	QUEZOZ	4523542343	Single	Priolo	Nhes	Nicole	2026-10-07 22:10:27.498355+08			1231231	3432432434234	21321321321	Nhes Priolo	0878657667	0c03bc9147f1d8ffdf53e2dc7e49f216.png	22e9f98ba7c6bc3b72d58d4b1046d845.png	089ce2b841ae66ef950f0cc67a6e433a.pdf	f6c90fdfb9bc505bf508ea5b9b0d1d75.png	f97f2da7956b7276b8e6abba7974faae.png		employee-23-health-card-2f1d4b158d096af9811a81e8.png		2026-10-07	\N	\N		2026-10-08 01:38:56.961615+08	employee-23-contract-61c4c79f4939e7f3891a65e9.png
\.


--
-- TOC entry 5062 (class 0 OID 16622)
-- Dependencies: 240
-- Data for Name: interviews; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.interviews (id, applicant_id, scheduled_at, interviewer, interview_type, location, notes, status, created_at) FROM stdin;
8	21	2026-10-22 09:00:00	nhes	In person	Lower Ground Floor, Ever Gotesco Commonwealth	pen	Completed	2026-10-07 21:42:50.387154+08
\.


--
-- TOC entry 5054 (class 0 OID 16537)
-- Dependencies: 232
-- Data for Name: leave_requests; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.leave_requests (id, user_id, employee_id, leave_type, start_date, end_date, days_count, reason, status, admin_remarks, created_at) FROM stdin;
\.


--
-- TOC entry 5066 (class 0 OID 24873)
-- Dependencies: 244
-- Data for Name: login_verifications; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.login_verifications (id, user_id, challenge_hash, otp_hash, attempts, expires_at, used_at, created_at) FROM stdin;
1	10	69830c3a183fff70c5da1d548bf2b77748afe4d90f1e67121aad6db3773cfb4d	$2y$10$.XW6Tc99vSJRlgOarxPiMeSOePeQsK.kXnTwepmzZ9oPqsFRCKUsO	0	2026-10-07 12:44:11.577576+08	2026-10-07 12:39:34.997555+08	2026-10-07 12:39:11.577576+08
2	10	c04ed0bd572404f75c2d1fa3867b750ae38256aac9ab604fba79e8147c6255e3	$2y$10$J7Gqsg9WoPglM5kl/EPlaepz.63zROc5N5yZ292IaWfBoy6kzNioe	0	2026-10-07 12:48:09.946859+08	2026-10-07 12:43:29.536912+08	2026-10-07 12:43:09.946859+08
3	4	a6525931ca0b67f47dcee00508426de9ab802ccb6540f3fea6f459539c9b6c36	$2y$10$kOcFiV39sg1eaQ480GjhZu02ff16yZ8PunPOBKTAm5mmEpEEPQC5y	0	2026-10-07 12:49:59.833181+08	2026-10-07 12:45:19.994314+08	2026-10-07 12:44:59.833181+08
19	4	09c350bc2d0bb2f13904f12fa935bf2368497d52800e19fc84605d4033037fec	$2y$10$TTkWS/Db6du3O7eONTC2TOlXGCcLrSiu8aiJT/cnhN/NValjunPFy	0	2026-10-07 22:00:04.287555+08	2026-10-07 21:55:26.484036+08	2026-10-07 21:55:04.287555+08
4	4	7a548835a3214ce60a055a60fdd8c167de58638f2f37f1b1deadc2ebc99d9350	$2y$10$0GrjKs5cmbh6Fb7ShgZiyehc2Zc6aysBUm97E8EveqNlJ6vUtGxOi	1	2026-10-07 12:54:29.914181+08	2026-10-07 12:50:41.736924+08	2026-10-07 12:49:29.914181+08
5	4	bf8276a5f9679eaf1dd015d2a6b147c0b6f7898588668b579ed0a209adb58ef4	$2y$10$RoEAO/Y60tzhWo8rU4ZSEOrZUZ8xiRGNMHxyqU62RV3/GKSf1Smeq	0	2026-10-07 13:01:21.213364+08	2026-10-07 12:56:53.189554+08	2026-10-07 12:56:21.213364+08
6	4	87245d849f599c8ecbed01553a27ba60f437cb8c5b66088b734d2d955911c570	$2y$10$2kp2w5nXhA/KWsNV//101OFKaJc39TfLa5YLC8ywrrLeZgC3tgqpy	0	2026-10-07 13:05:41.968262+08	2026-10-07 13:01:14.89024+08	2026-10-07 13:00:41.968262+08
7	10	8d94ccd44d99577519edca12a19e0a04a1238377037dcb56437d4d61864c5539	$2y$10$4Wc9M4zxhSlJoyJM7EEnt.zoQLqIVZmhOA0kbJdwCvXlEe5dj0PhG	0	2026-10-07 19:51:39.592323+08	2026-10-07 19:47:19.297034+08	2026-10-07 19:46:39.592323+08
8	4	37556253028b82c2f3bd713277f45c34dc144c604c218eee224ecf3b24e22685	$2y$10$wdme4ijj0iEsKKCnubgQEOCDkCNyBBemjO/2ARf6kUQINxdrrgvbi	0	2026-10-07 19:54:39.598193+08	2026-10-07 19:50:24.259627+08	2026-10-07 19:49:39.598193+08
9	4	836480fd99a85e37b8eb1be2f6ecd3534994ff4d39b6115532d36e2d25648327	$2y$10$QEq0cCEI0bLwT4rGBUeLR.Fzs7kChGoErPjnrcG58p/FUeuc8b2pG	0	2026-10-07 20:10:42.687004+08	2026-10-07 20:06:04.203344+08	2026-10-07 20:05:42.687004+08
10	10	7eb1e8a0ceb40362527bc083380631a8315f32c12405360d58774a6b37baae26	$2y$10$cO78p/IvuCuFaVruG5QV/OXHpdBoIineHylMCSILmcJFycS59..7S	0	2026-10-07 20:17:02.015157+08	2026-10-07 20:12:28.645914+08	2026-10-07 20:12:02.015157+08
11	10	9a4f9975f16142a63bc03766607645489607041257f33036574a31b386f88870	$2y$10$7ieZTcQQ.DNIbOb7poA4b.VfEbeSoZkqhL4r8wzKkWP.CsveQD2fa	0	2026-10-07 20:59:54.936798+08	2026-10-07 20:55:37.683289+08	2026-10-07 20:54:54.936798+08
12	4	5247d62ad07d616abc4fe1415d8f5de2a75fb22d946e70d9a04482edc87d08b5	$2y$10$qVCt5cn3Q13qJAt2CdrRPu2Q5isZRW9c3CoT/8/I5f6PYy6VUI/aC	0	2026-10-07 21:01:16.820186+08	2026-10-07 20:56:41.694293+08	2026-10-07 20:56:16.820186+08
13	4	84698c2f174fc7f6b9160a21b284a9d13e78cf50873e82996e44f344e195b215	$2y$10$jarRJiFI5ifN0OX3.FfOLe9HUyvkBB2HEKHwjeQWhso7krWV77Vi6	0	2026-10-07 21:06:41.046293+08	2026-10-07 21:02:08.027397+08	2026-10-07 21:01:41.046293+08
14	4	e18ed1ab93872e77d92347e0b5abd73e1d11185838d093326702674e23d56f20	$2y$10$kmFGobzvpRsifu86bJW43OjkD69CQ2zfsTkCywSNfES1FxVVq6PAK	0	2026-10-07 21:29:55.410601+08	2026-10-07 21:25:27.908865+08	2026-10-07 21:24:55.410601+08
15	4	f75842e12d851cb18a0f5112c5578f0f8c3246e4d33437dcb58dcf8e784992b7	$2y$10$lxQ0.1RKqgSd0kp9fQVmh.2DFhKMnLlvZmpDzFivGdlZXjXaO1CBu	0	2026-10-07 21:31:12.036262+08	2026-10-07 21:26:31.898783+08	2026-10-07 21:26:12.036262+08
16	10	e7cce4781267e022d5f17d25b684c5390b28932192cd5985605e011dc79dd54f	$2y$10$3oAIh3Yq6svt7FUSwCTjWexWTg1bG3MlZZfT.Ibcs3b7xhHtDjHGG	0	2026-10-07 21:40:48.273204+08	2026-10-07 21:36:13.394316+08	2026-10-07 21:35:48.273204+08
17	10	b3dcca0333b58919c0bff71a64398c3a0bb39eddcef65b6df8c6fc4a06b1f952	$2y$10$uiDqJ2x1EMq/1U2.hJFrhOmWSry8gQBirxnpXNvYlPEuAQK/Uc55G	1	2026-10-07 21:48:46.972934+08	2026-10-07 21:44:20.50035+08	2026-10-07 21:43:46.972934+08
18	4	781c92ab63a346f0055b1bfdcb38a5e1259a637e5a21d60933831bee3c77b746	$2y$10$noK86P3A43yC8/.aJk2qfu5sPlv.8xXSkDEXQokHjnMzcmkAoebM6	0	2026-10-07 21:58:12.154752+08	2026-10-07 21:53:49.892446+08	2026-10-07 21:53:12.154752+08
20	10	a1cfe970b2c1b19766b813c2bb883e157e727f49ed4f92a6e8b8be01b560b96c	$2y$10$qhDn7Df6vlHQH5shvCjYZeaLasJW8dBthDrWhCtEr4vObLKweaRZm	0	2026-10-07 22:01:06.955962+08	2026-10-07 21:56:26.212918+08	2026-10-07 21:56:06.955962+08
21	4	68ac67c4b8aae3f212e4bcda0e86833c021187cbb8bfbb683b6a36d99fefad7e	$2y$10$Mujes/i69tWJWWjUvK2KreCtb9epslX/22VlhbZ33JyK2nIOqtCDa	0	2026-10-07 22:02:56.976888+08	2026-10-07 21:58:16.372468+08	2026-10-07 21:57:56.976888+08
22	4	6a9f22291b9f6de4501f358bd8f0bf1caf1b579ca31573ac1119dfb8c20f5871	$2y$10$3S2JX6jcd3sxhYKojOpjAuTIHwzJD72vnIEoF5KPEfCbBoyZaS7dK	0	2026-10-07 22:09:44.624048+08	2026-10-07 22:05:02.045653+08	2026-10-07 22:04:44.624048+08
23	4	9e4a0f8cff73d696955f7de9cc880ad959d35bae4134d62ec1f26a7d66d42aa5	$2y$10$NynE5EE0BamDDYH2U/MR4.X0Hg6gJKxBWq8VNqbHGKb6BV/XUbpiu	0	2026-10-08 01:04:48.07058+08	2026-10-08 01:00:10.289968+08	2026-10-08 00:59:48.07058+08
24	10	c263430d7b4e8f5958ba02ec740ab1316bb1aa1b6bd8797e021fb139b2f59c7d	$2y$10$v4s.gG4edT5FOeUd32urVup1Uy.gysko0aWc.EnCqqfN9Osqf3WKS	0	2026-10-08 01:11:37.109914+08	2026-10-08 01:06:51.731592+08	2026-10-08 01:06:37.109914+08
25	4	877afca3b9735e0eeb1fc65c49d27598a8e4aeb65e20e479cc6444c89d576ecb	$2y$10$MiHI/f6pTDJ1Kk.951oF4.4qoMxRwGSTiGq.TDHdiy3oTj0hFjwG2	0	2026-10-08 01:47:41.703884+08	2026-10-08 01:43:55.202658+08	2026-10-08 01:42:41.703884+08
26	4	e42c58b8d032f99627ecae9e451c1b7ad69e15679a61a7ed1ec09b4d630b724f	$2y$10$GCNHDG.f3UetNEnNMAP58OMJRUFqSlrA6EMkMjZBujF4ins7fpWqe	0	2026-10-08 01:48:55.202658+08	2026-10-08 01:44:30.140218+08	2026-10-08 01:43:55.202658+08
27	10	664cfda305d090e346ae751ba052847f1ee149ccd15435f8bd161b567ba223c6	$2y$10$yTBOQU6vtq8tlipaaEWSeO2lFilAZ682ldnIi2pjpFxf/HwIp/Jh2	0	2026-10-08 01:50:50.160347+08	2026-10-08 01:46:54.137124+08	2026-10-08 01:45:50.160347+08
28	10	72755087a9d56a900c08744e0737f3ccdbbe59586fb319989a709e7320a25717	$2y$10$k8OggIhL0eYRCeIktXuHW.i.nb.O..lJafHhZShwTRfkEEqI8R0Oa	0	2026-10-08 02:02:36.750314+08	2026-10-08 01:57:55.949066+08	2026-10-08 01:57:36.750314+08
29	10	4da912cb40c981a2a61114e684aa0ad4f65fc537cf7d9b2692bbf5b95afe933b	$2y$10$GCWPaCpnNWMHBPS/Q5PgR.Tpvs3xYqmUWcwg5OEWbTTP6nNxOPHqi	0	2026-10-08 02:28:28.614935+08	2026-10-08 02:23:45.592443+08	2026-10-08 02:23:28.614935+08
30	4	a56505d9a510cfbf89c06af09dfaaf96864ecf0b52eefdfc6a2fc4201e992a2e	$2y$10$uGQB9hsS0dF.J5BzB./W8O6sw.vX1rLPKUwQVHmfQdQCTF71EZgyq	0	2026-10-08 02:29:04.864107+08	2026-10-08 02:24:56.739411+08	2026-10-08 02:24:04.864107+08
31	10	abf55cc654336415b9ee44848b6a09742ebb90967bd9cd9edf0e63a2add926a8	$2y$10$Xh4.F8XMVSSOpYH9fW5oR.RF8ggvRWfZc49HskYJkvmxbMK6cOuI2	1	2026-10-08 04:40:02.548842+08	2026-10-08 04:35:50.965063+08	2026-10-08 04:35:02.548842+08
32	4	6bf3008d4dea4b471e6058897e090e9f39c3b68537d73557e8316ac5b81f7b58	$2y$10$dwn56pAOgNTgX7ejVz.zJ.PvIoz8WyxEe6ckjzT66leQ5qB5QMk36	1	2026-10-08 04:41:37.48069+08	2026-10-08 04:37:35.730678+08	2026-10-08 04:36:37.48069+08
\.


--
-- TOC entry 5050 (class 0 OID 16485)
-- Dependencies: 228
-- Data for Name: onboarding_tasks; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.onboarding_tasks (id, employee_id, task, status, due_date, created_at) FROM stdin;
79	23	Orientation & Company Policy Review	Completed	2026-10-10	2026-10-07 22:10:27.498355+08
80	23	Role-Specific Training	Completed	2026-10-14	2026-10-07 22:10:27.498355+08
81	23	Complete Required Initial Training	Completed	2026-11-06	2026-10-07 22:10:27.498355+08
77	23	Contract Signed	Completed	2026-10-07	2026-10-07 22:10:27.498355+08
78	23	Health Card Picture	Completed	2026-10-07	2026-10-07 22:10:27.498355+08
\.


--
-- TOC entry 5052 (class 0 OID 16518)
-- Dependencies: 230
-- Data for Name: password_resets; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.password_resets (id, user_id, otp_hash, reset_token_hash, expires_at, attempts, verified_at, used_at, created_at) FROM stdin;
4	10	$2y$10$KzN.LYyM6yDoGkP9AppNzOnU4Z67kjrFoHBIvk0uXVWoIHSfyaC/G	103ad2b604a90302d585ae02f9fe55d8eef16e3fe01f2bc9f62639a9047f4df2	2026-10-05 16:53:26.455961+08	0	2026-10-05 16:48:51.874523+08	2026-10-05 16:49:06.214928+08	2026-10-05 16:48:26.455961+08
\.


--
-- TOC entry 5058 (class 0 OID 16577)
-- Dependencies: 236
-- Data for Name: payslips; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.payslips (id, user_id, employee_id, pay_period, pay_date, basic_salary, allowances, deductions, net_pay, status, created_at) FROM stdin;
\.


--
-- TOC entry 5064 (class 0 OID 24831)
-- Dependencies: 242
-- Data for Name: system_activities; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.system_activities (id, actor_id, actor_name, actor_role, activity, created_at) FROM stdin;
1	4	Admin User	admin	created a full-access Admin account for Admin	2026-10-05 16:37:46.812246+08
2	4	Admin User	admin	changed Admin User job title to Human Resources while retaining admin access	2026-10-05 16:37:46.812246+08
119	4	Human Resources	hr	logged in	2026-10-07 12:50:41.876496+08
122	7	Admin	admin	logged in	2026-10-07 19:47:19.409623+08
5	\N	Public user		reset their password	2026-10-05 16:49:06.320563+08
125	9	Human Resources	hr	logged in	2026-10-07 20:06:04.333639+08
128	10	Admin	admin	logged in	2026-10-07 20:12:28.7704+08
8	4	Human Resources	admin	updated the admin account name to Human Resources	2026-10-05 16:52:08.168697+08
131	13	Human Resources	hr	logged in	2026-10-07 21:02:08.142647+08
134	\N	Applicant	applicant	submitted an application	2026-10-07 21:35:22.306118+08
137	16	Admin	admin	scheduled an interview	2026-10-07 21:42:56.466603+08
140	19	Human Resources	hr	logged in	2026-10-07 21:55:26.609144+08
143	22	Human Resources	hr	logged in	2026-10-07 22:05:02.171377+08
146	24	Admin	admin	logged in	2026-10-08 01:06:51.856952+08
149	24	Admin	admin	updated an onboarding task	2026-10-08 01:32:18.860076+08
152	24	Admin	admin	updated an employee category	2026-10-08 01:33:39.610042+08
155	28	Admin	admin	logged in	2026-10-08 01:57:56.058375+08
158	29	Admin	admin	logged in	2026-10-08 02:23:45.705173+08
161	29	Admin	admin	updated an employee category	2026-10-08 02:26:31.878657+08
163	31	Admin	admin	logged in	2026-10-08 04:35:51.089571+08
33	4	Human Resources	admin	updated an onboarding task	2026-10-05 20:05:47.145643+08
34	4	Human Resources	admin	updated an onboarding task	2026-10-05 20:05:48.584243+08
35	4	Human Resources	admin	updated an onboarding task	2026-10-05 20:05:50.217675+08
53	10	Admin	admin	updated an employee category	2026-10-05 22:12:45.317812+08
54	10	Admin	admin	updated an employee category	2026-10-05 22:12:48.5788+08
55	10	Admin	admin	updated an employee category	2026-10-05 22:12:51.569796+08
58	10	Admin	admin	updated an employee category	2026-10-05 22:36:28.755431+08
64	\N	Applicant	applicant	submitted an application	2026-10-06 00:02:32.441287+08
69	4	Human Resources	admin	updated an applicant decision	2026-10-06 00:26:43.644583+08
70	\N	Applicant	applicant	submitted an application	2026-10-06 00:36:20.383887+08
71	4	Human Resources	admin	updated an applicant decision	2026-10-06 00:37:22.134317+08
72	4	Human Resources	admin	scheduled an interview	2026-10-06 00:39:59.067534+08
73	4	Human Resources	admin	updated an interview	2026-10-06 00:46:09.871504+08
75	10	Admin	admin	updated an employee category	2026-10-06 00:57:18.072542+08
76	10	Admin	admin	updated an employee category	2026-10-06 00:57:38.502965+08
77	10	Admin	admin	updated an employee category	2026-10-06 00:57:40.370571+08
90	4	Human Resources	hr	updated an onboarding task	2026-10-07 09:21:35.874524+08
91	4	Human Resources	hr	updated an onboarding task	2026-10-07 09:21:38.93974+08
92	4	Human Resources	hr	updated an onboarding task	2026-10-07 09:21:40.849488+08
96	10	Admin	admin	published an announcement	2026-10-07 11:01:20.402591+08
98	\N	Applicant	applicant	submitted an application	2026-10-07 11:34:29.193154+08
101	4	Human Resources	hr	updated an applicant decision	2026-10-07 11:41:05.410792+08
102	\N	Applicant	applicant	submitted an application	2026-10-07 11:43:32.049541+08
105	4	Human Resources	hr	updated an applicant decision	2026-10-07 11:51:12.299782+08
106	4	Human Resources	hr	scheduled an interview	2026-10-07 11:51:56.128339+08
107	4	Human Resources	hr	updated an interview	2026-10-07 11:52:21.12112+08
108	4	Human Resources	hr	updated an onboarding task	2026-10-07 11:54:39.496092+08
120	5	Human Resources	hr	logged in	2026-10-07 12:56:53.327957+08
123	8	Human Resources	hr	logged in	2026-10-07 19:50:24.384631+08
126	9	Human Resources	hr	updated an applicant decision	2026-10-07 20:06:58.24432+08
129	11	Admin	admin	logged in	2026-10-07 20:55:37.808801+08
132	14	Human Resources	hr	logged in	2026-10-07 21:25:28.033426+08
135	16	Admin	admin	logged in	2026-10-07 21:36:13.507484+08
138	17	Admin	admin	logged in	2026-10-07 21:44:20.614042+08
141	20	Admin	admin	logged in	2026-10-07 21:56:26.327584+08
144	22	Human Resources	hr	updated an interview	2026-10-07 22:10:27.650196+08
147	24	Admin	admin	updated an onboarding task	2026-10-08 01:32:14.543786+08
3	4	Admin User	admin	logged in	2026-10-05 16:40:20.830691+08
4	4	Admin User	admin	logged in	2026-10-05 16:43:00.999188+08
6	10	Admin	admin	logged in	2026-10-05 16:49:15.258929+08
7	4	Admin User	admin	logged in	2026-10-05 16:50:24.722763+08
9	10	Admin	admin	logged in	2026-10-05 16:52:50.156941+08
10	4	Human Resources	admin	logged in	2026-10-05 16:55:22.502645+08
11	10	Admin	admin	logged in	2026-10-05 17:00:41.386191+08
12	10	Admin	admin	logged in	2026-10-05 17:14:18.521548+08
13	10	Admin	admin	logged in	2026-10-05 17:16:36.443151+08
14	4	Human Resources	admin	logged in	2026-10-05 17:22:04.53048+08
15	10	Admin	admin	logged in	2026-10-05 17:25:29.166901+08
16	10	Admin	admin	logged in	2026-10-05 17:47:42.757089+08
17	4	Human Resources	admin	logged in	2026-10-05 17:54:58.805126+08
18	10	Admin	admin	logged in	2026-10-05 17:55:25.419917+08
19	10	Admin	admin	logged in	2026-10-05 17:56:08.365111+08
20	4	Human Resources	admin	logged in	2026-10-05 17:56:33.244279+08
21	10	Admin	admin	logged in	2026-10-05 17:57:46.659722+08
22	4	Human Resources	admin	logged in	2026-10-05 18:00:26.895286+08
23	4	Human Resources	admin	logged in	2026-10-05 18:09:12.639521+08
24	4	Human Resources	admin	logged in	2026-10-05 18:19:03.177396+08
25	10	Admin	admin	logged in	2026-10-05 18:20:19.851014+08
26	10	Admin	admin	logged in	2026-10-05 18:36:53.974588+08
27	10	Admin	admin	logged in	2026-10-05 18:41:44.2537+08
28	10	Admin	admin	logged in	2026-10-05 19:26:44.567334+08
29	10	Admin	admin	logged in	2026-10-05 19:41:39.027242+08
30	4	Human Resources	admin	logged in	2026-10-05 19:46:13.312441+08
31	10	Admin	admin	logged in	2026-10-05 19:46:49.299168+08
32	4	Human Resources	admin	logged in	2026-10-05 20:01:27.32682+08
36	4	Human Resources	admin	logged in	2026-10-05 20:16:38.36638+08
37	10	Admin	admin	logged in	2026-10-05 20:20:43.292094+08
38	10	Admin	admin	logged in	2026-10-05 20:24:13.666231+08
39	10	Admin	admin	logged in	2026-10-05 20:33:40.76568+08
40	10	Admin	admin	logged in	2026-10-05 20:58:43.748599+08
41	10	Admin	admin	logged in	2026-10-05 21:04:13.695781+08
42	4	Human Resources	admin	logged in	2026-10-05 21:05:24.463083+08
43	4	Human Resources	admin	logged in	2026-10-05 21:09:32.954317+08
44	10	Admin	admin	logged in	2026-10-05 21:09:51.367235+08
45	4	Human Resources	admin	logged in	2026-10-05 21:10:39.044898+08
46	10	Admin	admin	logged in	2026-10-05 21:21:33.763081+08
47	10	Admin	admin	logged in	2026-10-05 21:24:55.257604+08
48	4	Human Resources	admin	logged in	2026-10-05 21:25:14.393211+08
49	10	Admin	admin	logged in	2026-10-05 21:28:53.36248+08
50	10	Admin	admin	logged in	2026-10-05 21:42:04.973567+08
51	10	Admin	admin	logged in	2026-10-05 21:54:29.548393+08
52	10	Admin	admin	logged in	2026-10-05 22:07:14.982411+08
56	10	Admin	admin	logged in	2026-10-05 22:17:46.748855+08
57	10	Admin	admin	logged in	2026-10-05 22:35:09.158587+08
59	4	Human Resources	admin	logged in	2026-10-05 22:37:19.888716+08
60	4	Human Resources	admin	logged in	2026-10-05 23:28:35.86732+08
61	10	Admin	admin	logged in	2026-10-05 23:29:46.346561+08
62	4	Human Resources	admin	logged in	2026-10-05 23:40:05.414476+08
63	4	Human Resources	admin	logged in	2026-10-05 23:58:59.500179+08
65	10	Admin	admin	logged in	2026-10-06 00:08:38.453223+08
66	4	Human Resources	admin	logged in	2026-10-06 00:09:27.49041+08
67	10	Admin	admin	logged in	2026-10-06 00:13:24.320658+08
68	4	Human Resources	admin	logged in	2026-10-06 00:16:42.325115+08
74	10	Admin	admin	logged in	2026-10-06 00:53:57.868163+08
78	4	Human Resources	hr	logged in	2026-10-06 01:14:18.776976+08
79	4	Human Resources	hr	logged in	2026-10-06 01:16:29.495735+08
80	4	Human Resources	hr	logged in	2026-10-06 01:20:33.789225+08
81	10	Admin	admin	logged in	2026-10-06 01:30:55.590341+08
82	10	Admin	admin	logged in	2026-10-06 01:39:01.763993+08
83	10	Admin	admin	logged in	2026-10-06 01:47:54.081934+08
84	10	Admin	admin	logged in	2026-10-06 02:06:47.560482+08
85	4	Human Resources	hr	logged in	2026-10-07 08:03:21.310143+08
86	10	Admin	admin	logged in	2026-10-07 08:16:59.369168+08
87	4	Human Resources	hr	logged in	2026-10-07 08:23:31.441555+08
88	10	Admin	admin	logged in	2026-10-07 08:46:30.484907+08
89	4	Human Resources	hr	logged in	2026-10-07 09:20:38.271838+08
93	4	Human Resources	hr	logged in	2026-10-07 10:35:07.016796+08
94	4	Human Resources	hr	logged in	2026-10-07 10:40:59.785368+08
95	10	Admin	admin	logged in	2026-10-07 10:52:47.927036+08
97	4	Human Resources	hr	logged in	2026-10-07 11:01:46.394928+08
99	4	Human Resources	hr	logged in	2026-10-07 11:34:43.307808+08
100	4	Human Resources	hr	logged in	2026-10-07 11:39:11.892782+08
103	4	Human Resources	hr	logged in	2026-10-07 11:45:15.659786+08
104	4	Human Resources	hr	logged in	2026-10-07 11:50:41.34357+08
150	24	Admin	admin	updated an employee category	2026-10-08 01:33:27.609932+08
153	26	Human Resources	hr	logged in	2026-10-08 01:44:30.266027+08
156	28	Admin	admin	updated an employee category	2026-10-08 01:58:03.792839+08
159	30	Human Resources	hr	logged in	2026-10-08 02:24:56.845571+08
109	4	Human Resources	hr	logged in	2026-10-07 12:04:15.2028+08
110	10	Admin	admin	logged in	2026-10-07 12:13:34.884101+08
111	4	Human Resources	hr	logged in	2026-10-07 12:15:05.135114+08
112	10	Admin	admin	logged in	2026-10-07 12:17:07.362246+08
113	4	Human Resources	hr	logged in	2026-10-07 12:18:07.794742+08
114	4	Human Resources	hr	logged in	2026-10-07 12:31:28.760312+08
115	10	Admin	admin	logged in	2026-10-07 12:34:21.833908+08
121	6	Human Resources	hr	logged in	2026-10-07 13:01:15.018058+08
124	\N	Applicant	applicant	submitted an application	2026-10-07 20:00:04.637582+08
127	9	Human Resources	hr	scheduled an interview	2026-10-07 20:08:46.482832+08
130	12	Human Resources	hr	logged in	2026-10-07 20:56:41.805039+08
133	15	Human Resources	hr	logged in	2026-10-07 21:26:32.004109+08
136	16	Admin	admin	updated an applicant decision	2026-10-07 21:42:07.207141+08
139	18	Human Resources	hr	logged in	2026-10-07 21:53:50.018248+08
142	21	Human Resources	hr	logged in	2026-10-07 21:58:16.496387+08
145	23	Human Resources	hr	logged in	2026-10-08 01:00:10.424318+08
148	24	Admin	admin	updated an onboarding task	2026-10-08 01:32:17.277625+08
151	24	Admin	admin	updated an employee category	2026-10-08 01:33:33.284672+08
154	27	Admin	admin	logged in	2026-10-08 01:46:54.261172+08
157	28	Admin	admin	updated an employee category	2026-10-08 02:18:10.945652+08
160	29	Admin	admin	updated an employee category	2026-10-08 02:26:26.598917+08
162	29	Admin	admin	updated an employee category	2026-10-08 02:28:01.561102+08
164	32	Human Resources	hr	logged in	2026-10-08 04:37:35.843964+08
\.


--
-- TOC entry 5040 (class 0 OID 16389)
-- Dependencies: 218
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, email, password, role, name, "position", department, employee_id, created_at) FROM stdin;
10	priolonhes447@gmail.com	$2y$10$LFR/enBsNwPdPXGCZHZpWecqN87AWNMiOqG2JABrzI9RZogKPVMZK	admin	Admin	HR Manager	Human Resources	ADMIN002	2026-10-05 16:37:46.812246+08
4	phnhes@gmail.com	$2y$10$u2X9dkac8EVClZMwVSggletJiHh2KZ/GirN9VI8aeplcgdtMTrbdS	hr	Human Resources	Human Resources	Human Resources	ADMIN001	2026-09-24 18:36:41.918391+08
9	nash447@gmail.com	$2y$10$Xx75hBlduddJ5LYOgh6C8.xpt0ZX3GGf9HRNH5dosLAQZCsUWqmpu	employee	Nhes Nvarro Tatay	Driver	HR	EMP001	2026-10-05 13:48:52.980879+08
12	pash447@gmail.com	$2y$10$HbgkYsH2Igb291ivD.l7UOwFMkfdHLNiE6Z1KgiVAMWkitAcF3K6S	employee	Nhes Nash Pash	Driver	HR	EMP002	2026-10-06 00:46:09.671986+08
13	cash@gmail.com	$2y$10$HEBmUIPkzTytTAWri3LQVuAHstEg829ooE8PeHSgk9Z5TYAHPc1mW	employee	Nhes Tash Pish	Driver	HR	EMP003	2026-10-07 11:52:20.917002+08
18	nicole123mmmm@gmail.com	$2y$10$MH8CkqglRbOrrbx6jNM7UejdemiZkU1uYzXU9eWn1Cy4c3ij7/wDS	employee	Nhes Nicole Priolo	Driver	HR	EMP004	2026-10-07 22:10:27.498355+08
\.


--
-- TOC entry 5086 (class 0 OID 0)
-- Dependencies: 225
-- Name: announcement_reads_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.announcement_reads_id_seq', 1, false);


--
-- TOC entry 5087 (class 0 OID 0)
-- Dependencies: 223
-- Name: announcements_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.announcements_id_seq', 4, true);


--
-- TOC entry 5088 (class 0 OID 0)
-- Dependencies: 221
-- Name: applicants_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.applicants_id_seq', 21, true);


--
-- TOC entry 5089 (class 0 OID 0)
-- Dependencies: 233
-- Name: attendance_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.attendance_id_seq', 1, true);


--
-- TOC entry 5090 (class 0 OID 0)
-- Dependencies: 237
-- Name: employee_documents_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.employee_documents_id_seq', 1, false);


--
-- TOC entry 5091 (class 0 OID 0)
-- Dependencies: 219
-- Name: employees_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.employees_id_seq', 23, true);


--
-- TOC entry 5092 (class 0 OID 0)
-- Dependencies: 239
-- Name: interviews_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.interviews_id_seq', 8, true);


--
-- TOC entry 5093 (class 0 OID 0)
-- Dependencies: 231
-- Name: leave_requests_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.leave_requests_id_seq', 1, false);


--
-- TOC entry 5094 (class 0 OID 0)
-- Dependencies: 243
-- Name: login_verifications_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.login_verifications_id_seq', 32, true);


--
-- TOC entry 5095 (class 0 OID 0)
-- Dependencies: 227
-- Name: onboarding_tasks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.onboarding_tasks_id_seq', 81, true);


--
-- TOC entry 5096 (class 0 OID 0)
-- Dependencies: 229
-- Name: password_resets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.password_resets_id_seq', 4, true);


--
-- TOC entry 5097 (class 0 OID 0)
-- Dependencies: 235
-- Name: payslips_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.payslips_id_seq', 1, false);


--
-- TOC entry 5098 (class 0 OID 0)
-- Dependencies: 241
-- Name: system_activities_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.system_activities_id_seq', 164, true);


--
-- TOC entry 5099 (class 0 OID 0)
-- Dependencies: 217
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_id_seq', 18, true);


--
-- TOC entry 4854 (class 2606 OID 16471)
-- Name: announcement_reads announcement_reads_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcement_reads
    ADD CONSTRAINT announcement_reads_pkey PRIMARY KEY (id);


--
-- TOC entry 4852 (class 2606 OID 16463)
-- Name: announcements announcements_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_pkey PRIMARY KEY (id);


--
-- TOC entry 4850 (class 2606 OID 16452)
-- Name: applicants applicants_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.applicants
    ADD CONSTRAINT applicants_pkey PRIMARY KEY (id);


--
-- TOC entry 4865 (class 2606 OID 16570)
-- Name: attendance attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_pkey PRIMARY KEY (id);


--
-- TOC entry 4869 (class 2606 OID 16608)
-- Name: employee_documents employee_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_pkey PRIMARY KEY (id);


--
-- TOC entry 4844 (class 2606 OID 16435)
-- Name: employees employees_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_email_key UNIQUE (email);


--
-- TOC entry 4846 (class 2606 OID 16433)
-- Name: employees employees_employee_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_employee_id_key UNIQUE (employee_id);


--
-- TOC entry 4848 (class 2606 OID 16431)
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (id);


--
-- TOC entry 4871 (class 2606 OID 16636)
-- Name: interviews interviews_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interviews
    ADD CONSTRAINT interviews_pkey PRIMARY KEY (id);


--
-- TOC entry 4863 (class 2606 OID 16550)
-- Name: leave_requests leave_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_pkey PRIMARY KEY (id);


--
-- TOC entry 4876 (class 2606 OID 24882)
-- Name: login_verifications login_verifications_challenge_hash_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.login_verifications
    ADD CONSTRAINT login_verifications_challenge_hash_key UNIQUE (challenge_hash);


--
-- TOC entry 4878 (class 2606 OID 24880)
-- Name: login_verifications login_verifications_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.login_verifications
    ADD CONSTRAINT login_verifications_pkey PRIMARY KEY (id);


--
-- TOC entry 4858 (class 2606 OID 16494)
-- Name: onboarding_tasks onboarding_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.onboarding_tasks
    ADD CONSTRAINT onboarding_tasks_pkey PRIMARY KEY (id);


--
-- TOC entry 4860 (class 2606 OID 16529)
-- Name: password_resets password_resets_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.password_resets
    ADD CONSTRAINT password_resets_pkey PRIMARY KEY (id);


--
-- TOC entry 4867 (class 2606 OID 16589)
-- Name: payslips payslips_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payslips
    ADD CONSTRAINT payslips_pkey PRIMARY KEY (id);


--
-- TOC entry 4874 (class 2606 OID 24838)
-- Name: system_activities system_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_activities
    ADD CONSTRAINT system_activities_pkey PRIMARY KEY (id);


--
-- TOC entry 4856 (class 2606 OID 16473)
-- Name: announcement_reads unique_user_announcement; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcement_reads
    ADD CONSTRAINT unique_user_announcement UNIQUE (user_id, announcement_id);


--
-- TOC entry 4837 (class 2606 OID 16403)
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- TOC entry 4839 (class 2606 OID 16405)
-- Name: users users_employee_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_employee_id_key UNIQUE (employee_id);


--
-- TOC entry 4841 (class 2606 OID 16401)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- TOC entry 4842 (class 1259 OID 24840)
-- Name: employees_archived_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX employees_archived_at_idx ON public.employees USING btree (archived_at, id DESC) WHERE (archived_at IS NOT NULL);


--
-- TOC entry 4879 (class 1259 OID 24888)
-- Name: login_verifications_user_created_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX login_verifications_user_created_idx ON public.login_verifications USING btree (user_id, created_at DESC);


--
-- TOC entry 4861 (class 1259 OID 16535)
-- Name: password_resets_user_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX password_resets_user_idx ON public.password_resets USING btree (user_id, created_at DESC);


--
-- TOC entry 4872 (class 1259 OID 24839)
-- Name: system_activities_created_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX system_activities_created_at_idx ON public.system_activities USING btree (created_at DESC, id DESC);


--
-- TOC entry 4892 (class 2620 OID 24850)
-- Name: applicants applicants_unique_person_name_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER applicants_unique_person_name_insert BEFORE INSERT ON public.applicants FOR EACH ROW EXECUTE FUNCTION public.enforce_unique_person_name();


--
-- TOC entry 4893 (class 2620 OID 24851)
-- Name: applicants applicants_unique_person_name_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER applicants_unique_person_name_update BEFORE UPDATE OF name, email, status ON public.applicants FOR EACH ROW EXECUTE FUNCTION public.enforce_unique_person_name();


--
-- TOC entry 4890 (class 2620 OID 24848)
-- Name: employees employees_unique_person_name_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER employees_unique_person_name_insert BEFORE INSERT ON public.employees FOR EACH ROW EXECUTE FUNCTION public.enforce_unique_person_name();


--
-- TOC entry 4891 (class 2620 OID 24849)
-- Name: employees employees_unique_person_name_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER employees_unique_person_name_update BEFORE UPDATE OF name, email ON public.employees FOR EACH ROW EXECUTE FUNCTION public.enforce_unique_person_name();


--
-- TOC entry 4880 (class 2606 OID 16479)
-- Name: announcement_reads announcement_reads_announcement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcement_reads
    ADD CONSTRAINT announcement_reads_announcement_id_fkey FOREIGN KEY (announcement_id) REFERENCES public.announcements(id) ON DELETE CASCADE;


--
-- TOC entry 4881 (class 2606 OID 16474)
-- Name: announcement_reads announcement_reads_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcement_reads
    ADD CONSTRAINT announcement_reads_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4885 (class 2606 OID 16571)
-- Name: attendance attendance_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4887 (class 2606 OID 16609)
-- Name: employee_documents employee_documents_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4888 (class 2606 OID 16637)
-- Name: interviews interviews_applicant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interviews
    ADD CONSTRAINT interviews_applicant_id_fkey FOREIGN KEY (applicant_id) REFERENCES public.applicants(id) ON DELETE CASCADE;


--
-- TOC entry 4884 (class 2606 OID 16551)
-- Name: leave_requests leave_requests_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4889 (class 2606 OID 24883)
-- Name: login_verifications login_verifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.login_verifications
    ADD CONSTRAINT login_verifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4882 (class 2606 OID 16495)
-- Name: onboarding_tasks onboarding_tasks_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.onboarding_tasks
    ADD CONSTRAINT onboarding_tasks_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 4883 (class 2606 OID 16530)
-- Name: password_resets password_resets_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.password_resets
    ADD CONSTRAINT password_resets_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4886 (class 2606 OID 16590)
-- Name: payslips payslips_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payslips
    ADD CONSTRAINT payslips_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


-- Completed on 2026-10-08 04:41:27

--
-- PostgreSQL database dump complete
--

\unrestrict MtvT7NavICG68QLTUMcajCAd9M6XL79jWvt6OG8vW46o9Hi1wpxOHwUKAhE86zJ

