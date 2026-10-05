--
-- PostgreSQL database dump
--

\restrict VtfONbDZTV1lbPobS5uPbrjIQnPyMpF6BESf6UaYw5PYhEKbFnOfvnYeAozqQMB

-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11

-- Started on 2026-10-06 01:58:59

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
-- TOC entry 243 (class 1255 OID 24843)
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
-- TOC entry 5055 (class 0 OID 0)
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
-- TOC entry 5056 (class 0 OID 0)
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
-- TOC entry 5057 (class 0 OID 0)
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
-- TOC entry 5058 (class 0 OID 0)
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
-- TOC entry 5059 (class 0 OID 0)
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
-- TOC entry 5060 (class 0 OID 0)
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
    status character varying(20) DEFAULT 'Scheduled'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT interviews_interview_type_check CHECK (((interview_type)::text = ANY ((ARRAY['In person'::character varying, 'Video'::character varying, 'Phone'::character varying])::text[]))),
    CONSTRAINT interviews_status_check CHECK (((status)::text = ANY ((ARRAY['Scheduled'::character varying, 'Completed'::character varying, 'Cancelled'::character varying, 'No Show'::character varying])::text[])))
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
-- TOC entry 5061 (class 0 OID 0)
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
-- TOC entry 5062 (class 0 OID 0)
-- Dependencies: 231
-- Name: leave_requests_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.leave_requests_id_seq OWNED BY public.leave_requests.id;


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
-- TOC entry 5063 (class 0 OID 0)
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
-- TOC entry 5064 (class 0 OID 0)
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
-- TOC entry 5065 (class 0 OID 0)
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
-- TOC entry 5066 (class 0 OID 0)
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
-- TOC entry 5067 (class 0 OID 0)
-- Dependencies: 217
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- TOC entry 4775 (class 2604 OID 16468)
-- Name: announcement_reads id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcement_reads ALTER COLUMN id SET DEFAULT nextval('public.announcement_reads_id_seq'::regclass);


--
-- TOC entry 4772 (class 2604 OID 16457)
-- Name: announcements id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcements ALTER COLUMN id SET DEFAULT nextval('public.announcements_id_seq'::regclass);


--
-- TOC entry 4741 (class 2604 OID 16440)
-- Name: applicants id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.applicants ALTER COLUMN id SET DEFAULT nextval('public.applicants_id_seq'::regclass);


--
-- TOC entry 4791 (class 2604 OID 16560)
-- Name: attendance id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance ALTER COLUMN id SET DEFAULT nextval('public.attendance_id_seq'::regclass);


--
-- TOC entry 4806 (class 2604 OID 16599)
-- Name: employee_documents id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee_documents ALTER COLUMN id SET DEFAULT nextval('public.employee_documents_id_seq'::regclass);


--
-- TOC entry 4707 (class 2604 OID 16410)
-- Name: employees id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees ALTER COLUMN id SET DEFAULT nextval('public.employees_id_seq'::regclass);


--
-- TOC entry 4812 (class 2604 OID 16625)
-- Name: interviews id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interviews ALTER COLUMN id SET DEFAULT nextval('public.interviews_id_seq'::regclass);


--
-- TOC entry 4784 (class 2604 OID 16540)
-- Name: leave_requests id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leave_requests ALTER COLUMN id SET DEFAULT nextval('public.leave_requests_id_seq'::regclass);


--
-- TOC entry 4777 (class 2604 OID 16488)
-- Name: onboarding_tasks id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.onboarding_tasks ALTER COLUMN id SET DEFAULT nextval('public.onboarding_tasks_id_seq'::regclass);


--
-- TOC entry 4781 (class 2604 OID 16523)
-- Name: password_resets id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.password_resets ALTER COLUMN id SET DEFAULT nextval('public.password_resets_id_seq'::regclass);


--
-- TOC entry 4798 (class 2604 OID 16580)
-- Name: payslips id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payslips ALTER COLUMN id SET DEFAULT nextval('public.payslips_id_seq'::regclass);


--
-- TOC entry 4818 (class 2604 OID 24834)
-- Name: system_activities id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_activities ALTER COLUMN id SET DEFAULT nextval('public.system_activities_id_seq'::regclass);


--
-- TOC entry 4702 (class 2604 OID 16392)
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- TOC entry 5033 (class 0 OID 16465)
-- Dependencies: 226
-- Data for Name: announcement_reads; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.announcement_reads (id, user_id, announcement_id, read_at) FROM stdin;
\.


--
-- TOC entry 5031 (class 0 OID 16454)
-- Dependencies: 224
-- Data for Name: announcements; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.announcements (id, title, content, author, created_at) FROM stdin;
3	Welcome to Our New Team Members	Please join us in welcoming the new hires joining the Engineering and Sales teams this month!	HR	2026-09-24 15:35:43.100574+08
1	Upcoming Town Hall Meeting	Join us this Friday at 3:00 PM for the quarterly review. Refreshments will be served!	Human Resources	2026-09-24 15:35:43.100574+08
2	New Office Hours	Effective next Monday, the office will open at 8:30 AM. Please adjust your schedules accordingly.	Human Resources	2026-09-24 15:35:43.100574+08
\.


--
-- TOC entry 5029 (class 0 OID 16437)
-- Dependencies: 222
-- Data for Name: applicants; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.applicants (id, name, surname, middle_name, first_name, "position", email, phone, applied_date, status, created_at, department, gender, address, date_of_birth, age, place_of_birth, tin, civil_status, emergency_contact, emergency_contact_name, emergency_contact_phone, id_photo_path, id_picture_path, resume_path, comments, sss_number, pag_ibig_number, nbi_number, sss_photo_path, pag_ibig_photo_path, nbi_photo_path, health_card_photo_path, psa_photo_path) FROM stdin;
12	Nhes Nvarro Priolo	Priolo	Nvarro	Nhes	Driver	priolonhes447@gmail.com	0894893847387483	2026-10-04	Rejected	2026-10-04 15:23:55.068503+08	General	Male	243 Dama De Noche St	2000-06-04	26	QUEZON	4523542343	Single	Nhes Priolo - 0878657667	Nhes Priolo	0878657667	25900a953f9afe9f17a8610373e9a390.png	f51f76dbe822d9167fd61171c927bc3c.png	6e2d1aff06829e02bfcca714a54f073d.png	wala								
16	Nhes Nvarro Pash	Pash	Nvarro	Nhes	Driver	pash@gmail.com	08948938473	2026-10-05	Interviewing	2026-10-06 00:02:32.384099+08	General	Male	243 Dama De Noche St	2001-06-07	25	QUEZON	4523542343		Nhes Priolo - 0878657667	Nhes Priolo	0878657667	880c85a59f269e36e41c2e1447c8d06d.png	260547fe546ef53d279715e10d25a069.png	fa5979d08cb3ae5178fc4af32d94e5e8.png		1231231	2321321321321	21321321321	ecad35b32f375bc6baf1f8f0d6b7a58a.png	81944b828dfb2577cd1e23458747fa38.png	9d77f880d06e772f36a9f6c59800edd0.png	fa3a3223b849c66b314f75a34580597e.png	73f795b44fb697d3a3fddd2f87b0fe37.png
13	Nhes Nvarro Patutuy	Patutuy	Nvarro	Nhes	Driver	nhes@gmai.com	08948938473	2026-10-04	Hired	2026-10-04 17:26:49.772557+08	General	Male	243 Dama De Noche St	2000-10-04	26	QUEZON	4523542343	Single	Nhes Priolo - 0878657667	Nhes Priolo	0878657667	2c0fb08cde1eb1939e8392a67c8ff926.png	199ae4da1ba5eeed644b42fd88af00d2.png	86a0075be5a28d8949b0514904ee4f40.png									
14	Nhes Nvarro Tutuy	Tutuy	Nvarro	Nhes	Driver	nhes447@gmail.com	09289389283	2026-10-04	Hired	2026-10-05 02:22:33.536052+08	General	Male	243 Dama De Noche St	2000-03-06	26	QUEZON	4523542343	Single	Nhes Priolo - 0878657667	Nhes Priolo	0878657667	b326b9eccddb74702ba315c203bef66a.png	844a7261504345af193acd6224f7de7b.png	00aef54004ef223e21754f0c0ea4aabd.png		1231231	2321321321321	21321321321	97d65dcf5805e44fd2fb8a58003b99c3.png	d61b47101900b5c355ef31340a3a7ce8.png	57f5c3d40c2b9f5acab0375fb7ddd0c7.png	72504183bb0550c5a1801996185c2d31.png	cc9b485166842c0badcf7890c276ff60.png
11	ANTHONY Nvarro ANTHONY	ANTHONY	Nvarro	ANTHONY	Driver	admin@travelandtours.com	0894893847387483	2026-10-02	Rejected	2026-10-02 11:12:48.432869+08	General	Male	23213dsdasdsa	2006-02-02	20	QUEZON	131231231232	Single	213213dasdsad - 21321321321	213213dasdsad	21321321321	c604224d7ddf8e2f9e7f638595b13e24.png	6c7510a2dfbb4978a13a4cbe67fad93b.png	4c1c2ba1a71d14dc0a65797248615c52.png									
17	Nhes Nash Pash	Pash	Nash	Nhes	Driver	pash447@gmail.com	08948938473	2026-10-05	Hired	2026-10-06 00:36:20.349988+08	General	Female	243 Dama De Noche St	2000-02-07	26	QUEZON	4523542343	Single	Nhes Priolo - 0878657667	Nhes Priolo	0878657667	f99c3d9646a7a439d770c606f8763eeb.png	d8765b231ece12cd27cba6ecdce08e52.png	\N			2321321321321	21321321321	de800dacc29a25325f6ee40cd42d740e.png	2dadbe3e1593274308d44162088cfa75.png	3d3c137e6e914187d733506e8690673d.png	b88462c4beeef7bfa45ee14028447bc6.png	e8a2f25061ab58f0bfdfe75deb057fc8.png
15	Nhes Nvarro Tatay	Tatay	Nvarro	Nhes	Driver	nash447@gmail.com	08948938473	2026-10-05	Hired	2026-10-05 13:46:33.164539+08	General	Male	243 Dama De Noche St	2000-07-19	26	QUEZON	4523542343	Married	Nhes Priolo - 0878657667	Nhes Priolo	0878657667	5b729b201e08c5c416e640c20a5efbf8.png	7af952f2a321c97949866d6050509ca7.png	842cc23aa270c7a78c43a6b25a75b17f.png		1231231	2321321321321	21321321321	3660b19cc43b631f335abf79eec957a3.png	5dc7c46bce8218b7f5e892d62ade75fa.png	4b03014fd78b91e5ce4f2c4c5f5d7bc1.png	fde499b4acdae8421d9113106332d639.png	9a841deb1087dd7bc49175e9a90c35e1.png
\.


--
-- TOC entry 5041 (class 0 OID 16557)
-- Dependencies: 234
-- Data for Name: attendance; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.attendance (id, user_id, employee_id, date, clock_in, clock_out, status, notes, created_at) FROM stdin;
\.


--
-- TOC entry 5045 (class 0 OID 16596)
-- Dependencies: 238
-- Data for Name: employee_documents; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.employee_documents (id, user_id, employee_id, doc_type, title, description, status, file_url, created_at) FROM stdin;
\.


--
-- TOC entry 5027 (class 0 OID 16407)
-- Dependencies: 220
-- Data for Name: employees; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.employees (id, employee_id, name, email, department, role, status, phone, address, date_of_birth, gender, emergency_contact, age, place_of_birth, tin, civil_status, last_name, first_name, middle_name, created_at, bank_name, bank_account, sss_number, pag_ibig_number, nbi_number, emergency_contact_name, emergency_contact_phone, id_photo_path, id_picture_path, resume_path, sss_photo_path, pag_ibig_photo_path, nbi_photo_path, health_card_photo_path, psa_photo_path, applied_date, archived_at, archived_by, comments, certificate_received_at) FROM stdin;
12	ADMIN002	Admin	priolonhes447@gmail.com	Human Resources	HR Manager	Active						0							2026-10-05 16:37:46.812246+08																	\N	\N		\N
6	ADMIN001	Human Resources	phnhes@gmail.com	Human Resources	Human Resources	Active						0							2026-09-24 18:36:41.918391+08																	\N	\N		\N
11	EMP001	Nhes Nvarro Tatay	nash447@gmail.com	General	Driver	Unhired	08948938473	243 Dama De Noche St	2000-07-19	Male	Nhes Priolo - 0878657667	26	QUEZON	4523542343	Married	Tatay	Nhes	Nvarro	2026-10-05 13:48:52.980879+08			1231231	2321321321321	21321321321	Nhes Priolo	0878657667	5b729b201e08c5c416e640c20a5efbf8.png	employee-11-0a00959f497213682008bbbe.png	842cc23aa270c7a78c43a6b25a75b17f.png	3660b19cc43b631f335abf79eec957a3.png	5dc7c46bce8218b7f5e892d62ade75fa.png	4b03014fd78b91e5ce4f2c4c5f5d7bc1.png	fde499b4acdae8421d9113106332d639.png	9a841deb1087dd7bc49175e9a90c35e1.png	2026-10-05	\N	\N	no show	2026-10-05 22:14:55.705024+08
17	EMP002	Nhes Nash Pash	pash447@gmail.com	General	Driver	Complete	08948938473	243 Dama De Noche St	2000-02-07	Female	Nhes Priolo - 0878657667	26	QUEZON	4523542343	Single	Pash	Nhes	Nash	2026-10-06 00:46:09.671986+08				2321321321321	21321321321	Nhes Priolo	0878657667	f99c3d9646a7a439d770c606f8763eeb.png	d8765b231ece12cd27cba6ecdce08e52.png		de800dacc29a25325f6ee40cd42d740e.png	2dadbe3e1593274308d44162088cfa75.png	3d3c137e6e914187d733506e8690673d.png	b88462c4beeef7bfa45ee14028447bc6.png	e8a2f25061ab58f0bfdfe75deb057fc8.png	2026-10-05	\N	\N		2026-10-06 01:02:00.735871+08
\.


--
-- TOC entry 5047 (class 0 OID 16622)
-- Dependencies: 240
-- Data for Name: interviews; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.interviews (id, applicant_id, scheduled_at, interviewer, interview_type, location, notes, status, created_at) FROM stdin;
1	12	2026-10-07 16:30:00	nhes	In person	Lower Ground Floor, Ever Gotesco Commonwealth	mag dala ng ballpen	Scheduled	2026-10-04 15:25:40.49307+08
2	13	2026-10-14 23:30:00	nhes	In person	Lower Ground Floor, Ever Gotesco Commonwealth	mag dala ng ballpen	Completed	2026-10-04 22:47:08.100521+08
3	14	2026-10-14 14:30:00	nhes	In person	Lower Ground Floor, Ever Gotesco Commonwealth	mag dala ng pen	Completed	2026-10-05 02:25:32.149668+08
4	15	2026-10-14 13:30:00	nhes	In person	Lower Ground Floor, Ever Gotesco Commonwealth	pen	Completed	2026-10-05 13:47:48.175202+08
5	17	2026-10-17 00:30:00	nhes	In person	Lower Ground Floor, Ever Gotesco Commonwealth	pen	Completed	2026-10-06 00:39:52.148246+08
\.


--
-- TOC entry 5039 (class 0 OID 16537)
-- Dependencies: 232
-- Data for Name: leave_requests; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.leave_requests (id, user_id, employee_id, leave_type, start_date, end_date, days_count, reason, status, admin_remarks, created_at) FROM stdin;
\.


--
-- TOC entry 5035 (class 0 OID 16485)
-- Dependencies: 228
-- Data for Name: onboarding_tasks; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.onboarding_tasks (id, employee_id, task, status, due_date, created_at) FROM stdin;
50	11	Orientation & Company Policy Review	Completed	2026-10-08	2026-10-05 13:48:52.980879+08
51	11	Role-Specific Training	Completed	2026-10-12	2026-10-05 13:48:52.980879+08
52	11	Complete Required Initial Training	Completed	2026-11-04	2026-10-05 13:48:52.980879+08
54	17	Orientation & Company Policy Review	Pending	2026-10-08	2026-10-06 00:46:09.671986+08
55	17	Role-Specific Training	Pending	2026-10-12	2026-10-06 00:46:09.671986+08
56	17	Complete Required Initial Training	Pending	2026-11-04	2026-10-06 00:46:09.671986+08
53	17	Contract Signed	Completed	2026-10-05	2026-10-06 00:46:09.671986+08
49	11	Contract Signed	Completed	2026-10-05	2026-10-05 13:48:52.980879+08
\.


--
-- TOC entry 5037 (class 0 OID 16518)
-- Dependencies: 230
-- Data for Name: password_resets; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.password_resets (id, user_id, otp_hash, reset_token_hash, expires_at, attempts, verified_at, used_at, created_at) FROM stdin;
4	10	$2y$10$KzN.LYyM6yDoGkP9AppNzOnU4Z67kjrFoHBIvk0uXVWoIHSfyaC/G	103ad2b604a90302d585ae02f9fe55d8eef16e3fe01f2bc9f62639a9047f4df2	2026-10-05 16:53:26.455961+08	0	2026-10-05 16:48:51.874523+08	2026-10-05 16:49:06.214928+08	2026-10-05 16:48:26.455961+08
\.


--
-- TOC entry 5043 (class 0 OID 16577)
-- Dependencies: 236
-- Data for Name: payslips; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.payslips (id, user_id, employee_id, pay_period, pay_date, basic_salary, allowances, deductions, net_pay, status, created_at) FROM stdin;
\.


--
-- TOC entry 5049 (class 0 OID 24831)
-- Dependencies: 242
-- Data for Name: system_activities; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.system_activities (id, actor_id, actor_name, actor_role, activity, created_at) FROM stdin;
1	4	Admin User	admin	created a full-access Admin account for Admin	2026-10-05 16:37:46.812246+08
2	4	Admin User	admin	changed Admin User job title to Human Resources while retaining admin access	2026-10-05 16:37:46.812246+08
3	4	Admin User	admin	signed in	2026-10-05 16:40:20.830691+08
4	4	Admin User	admin	signed in	2026-10-05 16:43:00.999188+08
5	\N	Public user		reset their password	2026-10-05 16:49:06.320563+08
6	10	Admin	admin	signed in	2026-10-05 16:49:15.258929+08
7	4	Admin User	admin	signed in	2026-10-05 16:50:24.722763+08
8	4	Human Resources	admin	updated the admin account name to Human Resources	2026-10-05 16:52:08.168697+08
9	10	Admin	admin	signed in	2026-10-05 16:52:50.156941+08
10	4	Human Resources	admin	signed in	2026-10-05 16:55:22.502645+08
11	10	Admin	admin	signed in	2026-10-05 17:00:41.386191+08
12	10	Admin	admin	signed in	2026-10-05 17:14:18.521548+08
13	10	Admin	admin	signed in	2026-10-05 17:16:36.443151+08
14	4	Human Resources	admin	signed in	2026-10-05 17:22:04.53048+08
15	10	Admin	admin	signed in	2026-10-05 17:25:29.166901+08
16	10	Admin	admin	signed in	2026-10-05 17:47:42.757089+08
17	4	Human Resources	admin	signed in	2026-10-05 17:54:58.805126+08
18	10	Admin	admin	signed in	2026-10-05 17:55:25.419917+08
19	10	Admin	admin	signed in	2026-10-05 17:56:08.365111+08
20	4	Human Resources	admin	signed in	2026-10-05 17:56:33.244279+08
21	10	Admin	admin	signed in	2026-10-05 17:57:46.659722+08
22	4	Human Resources	admin	signed in	2026-10-05 18:00:26.895286+08
23	4	Human Resources	admin	signed in	2026-10-05 18:09:12.639521+08
24	4	Human Resources	admin	signed in	2026-10-05 18:19:03.177396+08
25	10	Admin	admin	signed in	2026-10-05 18:20:19.851014+08
26	10	Admin	admin	signed in	2026-10-05 18:36:53.974588+08
27	10	Admin	admin	signed in	2026-10-05 18:41:44.2537+08
28	10	Admin	admin	signed in	2026-10-05 19:26:44.567334+08
29	10	Admin	admin	signed in	2026-10-05 19:41:39.027242+08
30	4	Human Resources	admin	signed in	2026-10-05 19:46:13.312441+08
31	10	Admin	admin	signed in	2026-10-05 19:46:49.299168+08
32	4	Human Resources	admin	signed in	2026-10-05 20:01:27.32682+08
33	4	Human Resources	admin	updated an onboarding task	2026-10-05 20:05:47.145643+08
34	4	Human Resources	admin	updated an onboarding task	2026-10-05 20:05:48.584243+08
35	4	Human Resources	admin	updated an onboarding task	2026-10-05 20:05:50.217675+08
36	4	Human Resources	admin	signed in	2026-10-05 20:16:38.36638+08
37	10	Admin	admin	signed in	2026-10-05 20:20:43.292094+08
38	10	Admin	admin	signed in	2026-10-05 20:24:13.666231+08
39	10	Admin	admin	signed in	2026-10-05 20:33:40.76568+08
40	10	Admin	admin	signed in	2026-10-05 20:58:43.748599+08
41	10	Admin	admin	signed in	2026-10-05 21:04:13.695781+08
42	4	Human Resources	admin	signed in	2026-10-05 21:05:24.463083+08
43	4	Human Resources	admin	signed in	2026-10-05 21:09:32.954317+08
44	10	Admin	admin	signed in	2026-10-05 21:09:51.367235+08
45	4	Human Resources	admin	signed in	2026-10-05 21:10:39.044898+08
46	10	Admin	admin	signed in	2026-10-05 21:21:33.763081+08
47	10	Admin	admin	signed in	2026-10-05 21:24:55.257604+08
48	4	Human Resources	admin	signed in	2026-10-05 21:25:14.393211+08
49	10	Admin	admin	signed in	2026-10-05 21:28:53.36248+08
50	10	Admin	admin	signed in	2026-10-05 21:42:04.973567+08
51	10	Admin	admin	signed in	2026-10-05 21:54:29.548393+08
52	10	Admin	admin	signed in	2026-10-05 22:07:14.982411+08
53	10	Admin	admin	updated an employee category	2026-10-05 22:12:45.317812+08
54	10	Admin	admin	updated an employee category	2026-10-05 22:12:48.5788+08
55	10	Admin	admin	updated an employee category	2026-10-05 22:12:51.569796+08
56	10	Admin	admin	signed in	2026-10-05 22:17:46.748855+08
57	10	Admin	admin	signed in	2026-10-05 22:35:09.158587+08
58	10	Admin	admin	updated an employee category	2026-10-05 22:36:28.755431+08
59	4	Human Resources	admin	signed in	2026-10-05 22:37:19.888716+08
60	4	Human Resources	admin	signed in	2026-10-05 23:28:35.86732+08
61	10	Admin	admin	signed in	2026-10-05 23:29:46.346561+08
62	4	Human Resources	admin	signed in	2026-10-05 23:40:05.414476+08
63	4	Human Resources	admin	signed in	2026-10-05 23:58:59.500179+08
64	\N	Applicant	applicant	submitted an application	2026-10-06 00:02:32.441287+08
65	10	Admin	admin	signed in	2026-10-06 00:08:38.453223+08
66	4	Human Resources	admin	signed in	2026-10-06 00:09:27.49041+08
67	10	Admin	admin	signed in	2026-10-06 00:13:24.320658+08
68	4	Human Resources	admin	signed in	2026-10-06 00:16:42.325115+08
69	4	Human Resources	admin	updated an applicant decision	2026-10-06 00:26:43.644583+08
70	\N	Applicant	applicant	submitted an application	2026-10-06 00:36:20.383887+08
71	4	Human Resources	admin	updated an applicant decision	2026-10-06 00:37:22.134317+08
72	4	Human Resources	admin	scheduled an interview	2026-10-06 00:39:59.067534+08
73	4	Human Resources	admin	updated an interview	2026-10-06 00:46:09.871504+08
74	10	Admin	admin	signed in	2026-10-06 00:53:57.868163+08
75	10	Admin	admin	updated an employee category	2026-10-06 00:57:18.072542+08
76	10	Admin	admin	updated an employee category	2026-10-06 00:57:38.502965+08
77	10	Admin	admin	updated an employee category	2026-10-06 00:57:40.370571+08
78	4	Human Resources	hr	signed in	2026-10-06 01:14:18.776976+08
79	4	Human Resources	hr	signed in	2026-10-06 01:16:29.495735+08
80	4	Human Resources	hr	signed in	2026-10-06 01:20:33.789225+08
81	10	Admin	admin	signed in	2026-10-06 01:30:55.590341+08
82	10	Admin	admin	signed in	2026-10-06 01:39:01.763993+08
83	10	Admin	admin	signed in	2026-10-06 01:47:54.081934+08
\.


--
-- TOC entry 5025 (class 0 OID 16389)
-- Dependencies: 218
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, email, password, role, name, "position", department, employee_id, created_at) FROM stdin;
9	nash447@gmail.com	$2y$10$Xx75hBlduddJ5LYOgh6C8.xpt0ZX3GGf9HRNH5dosLAQZCsUWqmpu	employee	Nhes Nvarro Tatay	Driver	General	EMP001	2026-10-05 13:48:52.980879+08
10	priolonhes447@gmail.com	$2y$10$LFR/enBsNwPdPXGCZHZpWecqN87AWNMiOqG2JABrzI9RZogKPVMZK	admin	Admin	HR Manager	Human Resources	ADMIN002	2026-10-05 16:37:46.812246+08
4	phnhes@gmail.com	$2y$10$u2X9dkac8EVClZMwVSggletJiHh2KZ/GirN9VI8aeplcgdtMTrbdS	hr	Human Resources	Human Resources	Human Resources	ADMIN001	2026-09-24 18:36:41.918391+08
12	pash447@gmail.com	$2y$10$HbgkYsH2Igb291ivD.l7UOwFMkfdHLNiE6Z1KgiVAMWkitAcF3K6S	employee	Nhes Nash Pash	Driver	General	EMP002	2026-10-06 00:46:09.671986+08
\.


--
-- TOC entry 5068 (class 0 OID 0)
-- Dependencies: 225
-- Name: announcement_reads_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.announcement_reads_id_seq', 1, false);


--
-- TOC entry 5069 (class 0 OID 0)
-- Dependencies: 223
-- Name: announcements_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.announcements_id_seq', 3, true);


--
-- TOC entry 5070 (class 0 OID 0)
-- Dependencies: 221
-- Name: applicants_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.applicants_id_seq', 17, true);


--
-- TOC entry 5071 (class 0 OID 0)
-- Dependencies: 233
-- Name: attendance_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.attendance_id_seq', 1, true);


--
-- TOC entry 5072 (class 0 OID 0)
-- Dependencies: 237
-- Name: employee_documents_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.employee_documents_id_seq', 1, false);


--
-- TOC entry 5073 (class 0 OID 0)
-- Dependencies: 219
-- Name: employees_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.employees_id_seq', 17, true);


--
-- TOC entry 5074 (class 0 OID 0)
-- Dependencies: 239
-- Name: interviews_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.interviews_id_seq', 5, true);


--
-- TOC entry 5075 (class 0 OID 0)
-- Dependencies: 231
-- Name: leave_requests_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.leave_requests_id_seq', 1, false);


--
-- TOC entry 5076 (class 0 OID 0)
-- Dependencies: 227
-- Name: onboarding_tasks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.onboarding_tasks_id_seq', 56, true);


--
-- TOC entry 5077 (class 0 OID 0)
-- Dependencies: 229
-- Name: password_resets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.password_resets_id_seq', 4, true);


--
-- TOC entry 5078 (class 0 OID 0)
-- Dependencies: 235
-- Name: payslips_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.payslips_id_seq', 1, false);


--
-- TOC entry 5079 (class 0 OID 0)
-- Dependencies: 241
-- Name: system_activities_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.system_activities_id_seq', 83, true);


--
-- TOC entry 5080 (class 0 OID 0)
-- Dependencies: 217
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_id_seq', 12, true);


--
-- TOC entry 4845 (class 2606 OID 16471)
-- Name: announcement_reads announcement_reads_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcement_reads
    ADD CONSTRAINT announcement_reads_pkey PRIMARY KEY (id);


--
-- TOC entry 4843 (class 2606 OID 16463)
-- Name: announcements announcements_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_pkey PRIMARY KEY (id);


--
-- TOC entry 4841 (class 2606 OID 16452)
-- Name: applicants applicants_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.applicants
    ADD CONSTRAINT applicants_pkey PRIMARY KEY (id);


--
-- TOC entry 4856 (class 2606 OID 16570)
-- Name: attendance attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_pkey PRIMARY KEY (id);


--
-- TOC entry 4860 (class 2606 OID 16608)
-- Name: employee_documents employee_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_pkey PRIMARY KEY (id);


--
-- TOC entry 4835 (class 2606 OID 16435)
-- Name: employees employees_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_email_key UNIQUE (email);


--
-- TOC entry 4837 (class 2606 OID 16433)
-- Name: employees employees_employee_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_employee_id_key UNIQUE (employee_id);


--
-- TOC entry 4839 (class 2606 OID 16431)
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (id);


--
-- TOC entry 4862 (class 2606 OID 16636)
-- Name: interviews interviews_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interviews
    ADD CONSTRAINT interviews_pkey PRIMARY KEY (id);


--
-- TOC entry 4854 (class 2606 OID 16550)
-- Name: leave_requests leave_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_pkey PRIMARY KEY (id);


--
-- TOC entry 4849 (class 2606 OID 16494)
-- Name: onboarding_tasks onboarding_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.onboarding_tasks
    ADD CONSTRAINT onboarding_tasks_pkey PRIMARY KEY (id);


--
-- TOC entry 4851 (class 2606 OID 16529)
-- Name: password_resets password_resets_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.password_resets
    ADD CONSTRAINT password_resets_pkey PRIMARY KEY (id);


--
-- TOC entry 4858 (class 2606 OID 16589)
-- Name: payslips payslips_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payslips
    ADD CONSTRAINT payslips_pkey PRIMARY KEY (id);


--
-- TOC entry 4865 (class 2606 OID 24838)
-- Name: system_activities system_activities_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_activities
    ADD CONSTRAINT system_activities_pkey PRIMARY KEY (id);


--
-- TOC entry 4847 (class 2606 OID 16473)
-- Name: announcement_reads unique_user_announcement; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcement_reads
    ADD CONSTRAINT unique_user_announcement UNIQUE (user_id, announcement_id);


--
-- TOC entry 4828 (class 2606 OID 16403)
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- TOC entry 4830 (class 2606 OID 16405)
-- Name: users users_employee_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_employee_id_key UNIQUE (employee_id);


--
-- TOC entry 4832 (class 2606 OID 16401)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- TOC entry 4833 (class 1259 OID 24840)
-- Name: employees_archived_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX employees_archived_at_idx ON public.employees USING btree (archived_at, id DESC) WHERE (archived_at IS NOT NULL);


--
-- TOC entry 4852 (class 1259 OID 16535)
-- Name: password_resets_user_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX password_resets_user_idx ON public.password_resets USING btree (user_id, created_at DESC);


--
-- TOC entry 4863 (class 1259 OID 24839)
-- Name: system_activities_created_at_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX system_activities_created_at_idx ON public.system_activities USING btree (created_at DESC, id DESC);


--
-- TOC entry 4877 (class 2620 OID 24850)
-- Name: applicants applicants_unique_person_name_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER applicants_unique_person_name_insert BEFORE INSERT ON public.applicants FOR EACH ROW EXECUTE FUNCTION public.enforce_unique_person_name();


--
-- TOC entry 4878 (class 2620 OID 24851)
-- Name: applicants applicants_unique_person_name_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER applicants_unique_person_name_update BEFORE UPDATE OF name, email, status ON public.applicants FOR EACH ROW EXECUTE FUNCTION public.enforce_unique_person_name();


--
-- TOC entry 4875 (class 2620 OID 24848)
-- Name: employees employees_unique_person_name_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER employees_unique_person_name_insert BEFORE INSERT ON public.employees FOR EACH ROW EXECUTE FUNCTION public.enforce_unique_person_name();


--
-- TOC entry 4876 (class 2620 OID 24849)
-- Name: employees employees_unique_person_name_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER employees_unique_person_name_update BEFORE UPDATE OF name, email ON public.employees FOR EACH ROW EXECUTE FUNCTION public.enforce_unique_person_name();


--
-- TOC entry 4866 (class 2606 OID 16479)
-- Name: announcement_reads announcement_reads_announcement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcement_reads
    ADD CONSTRAINT announcement_reads_announcement_id_fkey FOREIGN KEY (announcement_id) REFERENCES public.announcements(id) ON DELETE CASCADE;


--
-- TOC entry 4867 (class 2606 OID 16474)
-- Name: announcement_reads announcement_reads_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcement_reads
    ADD CONSTRAINT announcement_reads_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4871 (class 2606 OID 16571)
-- Name: attendance attendance_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4873 (class 2606 OID 16609)
-- Name: employee_documents employee_documents_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4874 (class 2606 OID 16637)
-- Name: interviews interviews_applicant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interviews
    ADD CONSTRAINT interviews_applicant_id_fkey FOREIGN KEY (applicant_id) REFERENCES public.applicants(id) ON DELETE CASCADE;


--
-- TOC entry 4870 (class 2606 OID 16551)
-- Name: leave_requests leave_requests_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4868 (class 2606 OID 16495)
-- Name: onboarding_tasks onboarding_tasks_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.onboarding_tasks
    ADD CONSTRAINT onboarding_tasks_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 4869 (class 2606 OID 16530)
-- Name: password_resets password_resets_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.password_resets
    ADD CONSTRAINT password_resets_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4872 (class 2606 OID 16590)
-- Name: payslips payslips_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payslips
    ADD CONSTRAINT payslips_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


-- Completed on 2026-10-06 01:59:00

--
-- PostgreSQL database dump complete
--

\unrestrict VtfONbDZTV1lbPobS5uPbrjIQnPyMpF6BESf6UaYw5PYhEKbFnOfvnYeAozqQMB

