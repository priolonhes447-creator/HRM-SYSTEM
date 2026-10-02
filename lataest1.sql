--
-- PostgreSQL database dump
--

\restrict y6FFUVpZABWrOdAdguJMrIYjUAPb4906WwoXFpgqxYUHa7OQM8rMRB0FTpj2gnw

-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11

-- Started on 2026-10-02 18:32:44

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
-- TOC entry 5012 (class 0 OID 0)
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
-- TOC entry 5013 (class 0 OID 0)
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
-- TOC entry 5014 (class 0 OID 0)
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
-- TOC entry 5015 (class 0 OID 0)
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
-- TOC entry 5016 (class 0 OID 0)
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
    CONSTRAINT employees_status_check CHECK (((status)::text = ANY ((ARRAY['Active'::character varying, 'On Leave'::character varying, 'Onboarding'::character varying, 'Inactive'::character varying])::text[])))
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
-- TOC entry 5017 (class 0 OID 0)
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
-- TOC entry 5018 (class 0 OID 0)
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
-- TOC entry 5019 (class 0 OID 0)
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
-- TOC entry 5020 (class 0 OID 0)
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
-- TOC entry 5021 (class 0 OID 0)
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
-- TOC entry 5022 (class 0 OID 0)
-- Dependencies: 235
-- Name: payslips_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.payslips_id_seq OWNED BY public.payslips.id;


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
    CONSTRAINT users_role_check CHECK (((role)::text = ANY ((ARRAY['admin'::character varying, 'employee'::character varying])::text[])))
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
-- TOC entry 5023 (class 0 OID 0)
-- Dependencies: 217
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- TOC entry 4745 (class 2604 OID 16468)
-- Name: announcement_reads id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcement_reads ALTER COLUMN id SET DEFAULT nextval('public.announcement_reads_id_seq'::regclass);


--
-- TOC entry 4742 (class 2604 OID 16457)
-- Name: announcements id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcements ALTER COLUMN id SET DEFAULT nextval('public.announcements_id_seq'::regclass);


--
-- TOC entry 4720 (class 2604 OID 16440)
-- Name: applicants id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.applicants ALTER COLUMN id SET DEFAULT nextval('public.applicants_id_seq'::regclass);


--
-- TOC entry 4761 (class 2604 OID 16560)
-- Name: attendance id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance ALTER COLUMN id SET DEFAULT nextval('public.attendance_id_seq'::regclass);


--
-- TOC entry 4776 (class 2604 OID 16599)
-- Name: employee_documents id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee_documents ALTER COLUMN id SET DEFAULT nextval('public.employee_documents_id_seq'::regclass);


--
-- TOC entry 4701 (class 2604 OID 16410)
-- Name: employees id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees ALTER COLUMN id SET DEFAULT nextval('public.employees_id_seq'::regclass);


--
-- TOC entry 4782 (class 2604 OID 16625)
-- Name: interviews id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interviews ALTER COLUMN id SET DEFAULT nextval('public.interviews_id_seq'::regclass);


--
-- TOC entry 4754 (class 2604 OID 16540)
-- Name: leave_requests id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leave_requests ALTER COLUMN id SET DEFAULT nextval('public.leave_requests_id_seq'::regclass);


--
-- TOC entry 4747 (class 2604 OID 16488)
-- Name: onboarding_tasks id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.onboarding_tasks ALTER COLUMN id SET DEFAULT nextval('public.onboarding_tasks_id_seq'::regclass);


--
-- TOC entry 4751 (class 2604 OID 16523)
-- Name: password_resets id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.password_resets ALTER COLUMN id SET DEFAULT nextval('public.password_resets_id_seq'::regclass);


--
-- TOC entry 4768 (class 2604 OID 16580)
-- Name: payslips id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payslips ALTER COLUMN id SET DEFAULT nextval('public.payslips_id_seq'::regclass);


--
-- TOC entry 4696 (class 2604 OID 16392)
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- TOC entry 4992 (class 0 OID 16465)
-- Dependencies: 226
-- Data for Name: announcement_reads; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.announcement_reads (id, user_id, announcement_id, read_at) FROM stdin;
\.


--
-- TOC entry 4990 (class 0 OID 16454)
-- Dependencies: 224
-- Data for Name: announcements; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.announcements (id, title, content, author, created_at) FROM stdin;
1	Upcoming Town Hall Meeting	Join us this Friday at 3:00 PM for the quarterly review. Refreshments will be served!	Admin User	2026-09-24 15:35:43.100574+08
2	New Office Hours	Effective next Monday, the office will open at 8:30 AM. Please adjust your schedules accordingly.	Admin User	2026-09-24 15:35:43.100574+08
3	Welcome to Our New Team Members	Please join us in welcoming the new hires joining the Engineering and Sales teams this month!	HR	2026-09-24 15:35:43.100574+08
\.


--
-- TOC entry 4988 (class 0 OID 16437)
-- Dependencies: 222
-- Data for Name: applicants; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.applicants (id, name, surname, middle_name, first_name, "position", email, phone, applied_date, status, created_at, department, gender, address, date_of_birth, age, place_of_birth, tin, civil_status, emergency_contact, emergency_contact_name, emergency_contact_phone, id_photo_path, id_picture_path, resume_path) FROM stdin;
11	ANTHONY Nvarro ANTHONY	ANTHONY	Nvarro	ANTHONY	Driver	admin@travelandtours.com	0894893847387483	2026-10-02	Interviewing	2026-10-02 11:12:48.432869+08	General	Male	23213dsdasdsa	2006-02-02	20	QUEZON	131231231232	Single	213213dasdsad - 21321321321	213213dasdsad	21321321321	c604224d7ddf8e2f9e7f638595b13e24.png	6c7510a2dfbb4978a13a4cbe67fad93b.png	4c1c2ba1a71d14dc0a65797248615c52.png
\.


--
-- TOC entry 5000 (class 0 OID 16557)
-- Dependencies: 234
-- Data for Name: attendance; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.attendance (id, user_id, employee_id, date, clock_in, clock_out, status, notes, created_at) FROM stdin;
\.


--
-- TOC entry 5004 (class 0 OID 16596)
-- Dependencies: 238
-- Data for Name: employee_documents; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.employee_documents (id, user_id, employee_id, doc_type, title, description, status, file_url, created_at) FROM stdin;
\.


--
-- TOC entry 4986 (class 0 OID 16407)
-- Dependencies: 220
-- Data for Name: employees; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.employees (id, employee_id, name, email, department, role, status, phone, address, date_of_birth, gender, emergency_contact, age, place_of_birth, tin, civil_status, last_name, first_name, middle_name, created_at, bank_name, bank_account) FROM stdin;
1	EMP001	Alice Johnson	alice@company.com	IT	Developer	Active	0917-111-1111	123 Tech St, Manila	1990-05-12	Female	0917-999-0001	0							2026-09-24 15:35:43.100574+08		
2	EMP002	Bob Smith	bob@company.com	Sales	Manager	Active	0918-222-2222	456 Sales Ave, Quezon City	1988-11-23	Male	0918-999-0002	0							2026-09-24 15:35:43.100574+08		
3	EMP003	Charlie Brown	charlie@company.com	HR	Recruiter	On Leave	0919-333-3333	789 HR Rd, Makati	1995-02-08	Male	0919-999-0003	0							2026-09-24 15:35:43.100574+08		
6	ADMIN001	Admin User	admin@gmail.com	Human Resources	HR Manager	Active						0							2026-09-24 18:36:41.918391+08		
8	EMP005	ANTHONY Nvarro ANTHONY	admin@travelandtours.com	General	Driver	Onboarding	0894893847387483	123edgd	2001-01-27	Male	Dfsdfdsf - 65765765767	25	QUEZON	2432453243	Single	ANTHONY	ANTHONY	Nvarro	2026-10-02 09:09:10.959206+08		
\.


--
-- TOC entry 5006 (class 0 OID 16622)
-- Dependencies: 240
-- Data for Name: interviews; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.interviews (id, applicant_id, scheduled_at, interviewer, interview_type, location, notes, status, created_at) FROM stdin;
\.


--
-- TOC entry 4998 (class 0 OID 16537)
-- Dependencies: 232
-- Data for Name: leave_requests; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.leave_requests (id, user_id, employee_id, leave_type, start_date, end_date, days_count, reason, status, admin_remarks, created_at) FROM stdin;
\.


--
-- TOC entry 4994 (class 0 OID 16485)
-- Dependencies: 228
-- Data for Name: onboarding_tasks; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.onboarding_tasks (id, employee_id, task, status, due_date, created_at) FROM stdin;
25	8	Contract Signed	Pending	2026-10-02	2026-10-02 09:09:10.976891+08
26	8	Email & Account Created	Pending	2026-10-02	2026-10-02 09:09:10.986009+08
27	8	IT Assets Assigned (Laptop, Peripherals)	Pending	2026-10-03	2026-10-02 09:09:10.98704+08
28	8	Company ID / Access Badge Issued	Pending	2026-10-04	2026-10-02 09:09:10.987939+08
29	8	Orientation & Company Policy Review	Pending	2026-10-05	2026-10-02 09:09:10.988791+08
30	8	Department Introductions & Buddy Assigned	Pending	2026-10-06	2026-10-02 09:09:10.989662+08
31	8	Role-Specific Training	Pending	2026-10-09	2026-10-02 09:09:10.990642+08
32	8	30-Day Check-in & Feedback Session	Pending	2026-11-01	2026-10-02 09:09:10.991317+08
\.


--
-- TOC entry 4996 (class 0 OID 16518)
-- Dependencies: 230
-- Data for Name: password_resets; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.password_resets (id, user_id, otp_hash, reset_token_hash, expires_at, attempts, verified_at, used_at, created_at) FROM stdin;
\.


--
-- TOC entry 5002 (class 0 OID 16577)
-- Dependencies: 236
-- Data for Name: payslips; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.payslips (id, user_id, employee_id, pay_period, pay_date, basic_salary, allowances, deductions, net_pay, status, created_at) FROM stdin;
\.


--
-- TOC entry 4984 (class 0 OID 16389)
-- Dependencies: 218
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, email, password, role, name, "position", department, employee_id, created_at) FROM stdin;
4	admin@gmail.com	$2y$10$u2X9dkac8EVClZMwVSggletJiHh2KZ/GirN9VI8aeplcgdtMTrbdS	admin	Admin User	HR Manager	Human Resources	ADMIN001	2026-09-24 18:36:41.918391+08
6	admin@travelandtours.com	$2y$10$bB0yhkqpkXqafubKEzKTUuqRAvCVb4tt6GD8bocNVKRi0i27iA1LO	employee	ANTHONY Nvarro ANTHONY	Driver	General	EMP005	2026-10-02 09:09:11.092768+08
\.


--
-- TOC entry 5024 (class 0 OID 0)
-- Dependencies: 225
-- Name: announcement_reads_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.announcement_reads_id_seq', 1, false);


--
-- TOC entry 5025 (class 0 OID 0)
-- Dependencies: 223
-- Name: announcements_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.announcements_id_seq', 3, true);


--
-- TOC entry 5026 (class 0 OID 0)
-- Dependencies: 221
-- Name: applicants_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.applicants_id_seq', 11, true);


--
-- TOC entry 5027 (class 0 OID 0)
-- Dependencies: 233
-- Name: attendance_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.attendance_id_seq', 1, true);


--
-- TOC entry 5028 (class 0 OID 0)
-- Dependencies: 237
-- Name: employee_documents_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.employee_documents_id_seq', 1, false);


--
-- TOC entry 5029 (class 0 OID 0)
-- Dependencies: 219
-- Name: employees_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.employees_id_seq', 8, true);


--
-- TOC entry 5030 (class 0 OID 0)
-- Dependencies: 239
-- Name: interviews_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.interviews_id_seq', 1, false);


--
-- TOC entry 5031 (class 0 OID 0)
-- Dependencies: 231
-- Name: leave_requests_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.leave_requests_id_seq', 1, false);


--
-- TOC entry 5032 (class 0 OID 0)
-- Dependencies: 227
-- Name: onboarding_tasks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.onboarding_tasks_id_seq', 32, true);


--
-- TOC entry 5033 (class 0 OID 0)
-- Dependencies: 229
-- Name: password_resets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.password_resets_id_seq', 2, true);


--
-- TOC entry 5034 (class 0 OID 0)
-- Dependencies: 235
-- Name: payslips_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.payslips_id_seq', 1, false);


--
-- TOC entry 5035 (class 0 OID 0)
-- Dependencies: 217
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_id_seq', 6, true);


--
-- TOC entry 4811 (class 2606 OID 16471)
-- Name: announcement_reads announcement_reads_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcement_reads
    ADD CONSTRAINT announcement_reads_pkey PRIMARY KEY (id);


--
-- TOC entry 4809 (class 2606 OID 16463)
-- Name: announcements announcements_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcements
    ADD CONSTRAINT announcements_pkey PRIMARY KEY (id);


--
-- TOC entry 4807 (class 2606 OID 16452)
-- Name: applicants applicants_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.applicants
    ADD CONSTRAINT applicants_pkey PRIMARY KEY (id);


--
-- TOC entry 4822 (class 2606 OID 16570)
-- Name: attendance attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_pkey PRIMARY KEY (id);


--
-- TOC entry 4826 (class 2606 OID 16608)
-- Name: employee_documents employee_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_pkey PRIMARY KEY (id);


--
-- TOC entry 4801 (class 2606 OID 16435)
-- Name: employees employees_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_email_key UNIQUE (email);


--
-- TOC entry 4803 (class 2606 OID 16433)
-- Name: employees employees_employee_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_employee_id_key UNIQUE (employee_id);


--
-- TOC entry 4805 (class 2606 OID 16431)
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (id);


--
-- TOC entry 4828 (class 2606 OID 16636)
-- Name: interviews interviews_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interviews
    ADD CONSTRAINT interviews_pkey PRIMARY KEY (id);


--
-- TOC entry 4820 (class 2606 OID 16550)
-- Name: leave_requests leave_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_pkey PRIMARY KEY (id);


--
-- TOC entry 4815 (class 2606 OID 16494)
-- Name: onboarding_tasks onboarding_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.onboarding_tasks
    ADD CONSTRAINT onboarding_tasks_pkey PRIMARY KEY (id);


--
-- TOC entry 4817 (class 2606 OID 16529)
-- Name: password_resets password_resets_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.password_resets
    ADD CONSTRAINT password_resets_pkey PRIMARY KEY (id);


--
-- TOC entry 4824 (class 2606 OID 16589)
-- Name: payslips payslips_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payslips
    ADD CONSTRAINT payslips_pkey PRIMARY KEY (id);


--
-- TOC entry 4813 (class 2606 OID 16473)
-- Name: announcement_reads unique_user_announcement; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcement_reads
    ADD CONSTRAINT unique_user_announcement UNIQUE (user_id, announcement_id);


--
-- TOC entry 4795 (class 2606 OID 16403)
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- TOC entry 4797 (class 2606 OID 16405)
-- Name: users users_employee_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_employee_id_key UNIQUE (employee_id);


--
-- TOC entry 4799 (class 2606 OID 16401)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- TOC entry 4818 (class 1259 OID 16535)
-- Name: password_resets_user_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX password_resets_user_idx ON public.password_resets USING btree (user_id, created_at DESC);


--
-- TOC entry 4829 (class 2606 OID 16479)
-- Name: announcement_reads announcement_reads_announcement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcement_reads
    ADD CONSTRAINT announcement_reads_announcement_id_fkey FOREIGN KEY (announcement_id) REFERENCES public.announcements(id) ON DELETE CASCADE;


--
-- TOC entry 4830 (class 2606 OID 16474)
-- Name: announcement_reads announcement_reads_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.announcement_reads
    ADD CONSTRAINT announcement_reads_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4834 (class 2606 OID 16571)
-- Name: attendance attendance_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4836 (class 2606 OID 16609)
-- Name: employee_documents employee_documents_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee_documents
    ADD CONSTRAINT employee_documents_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4837 (class 2606 OID 16637)
-- Name: interviews interviews_applicant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.interviews
    ADD CONSTRAINT interviews_applicant_id_fkey FOREIGN KEY (applicant_id) REFERENCES public.applicants(id) ON DELETE CASCADE;


--
-- TOC entry 4833 (class 2606 OID 16551)
-- Name: leave_requests leave_requests_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4831 (class 2606 OID 16495)
-- Name: onboarding_tasks onboarding_tasks_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.onboarding_tasks
    ADD CONSTRAINT onboarding_tasks_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(id) ON DELETE CASCADE;


--
-- TOC entry 4832 (class 2606 OID 16530)
-- Name: password_resets password_resets_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.password_resets
    ADD CONSTRAINT password_resets_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- TOC entry 4835 (class 2606 OID 16590)
-- Name: payslips payslips_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payslips
    ADD CONSTRAINT payslips_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


-- Completed on 2026-10-02 18:32:45

--
-- PostgreSQL database dump complete
--

\unrestrict y6FFUVpZABWrOdAdguJMrIYjUAPb4906WwoXFpgqxYUHa7OQM8rMRB0FTpj2gnw

