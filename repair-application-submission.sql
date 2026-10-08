-- Non-destructive submission repair. Apply before deploying the updated PHP/form.
-- Preserve existing applicants, documents, and person-name validation.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '30s';
ALTER TABLE public.applicants ADD COLUMN IF NOT EXISTS submission_key VARCHAR(64);
CREATE UNIQUE INDEX IF NOT EXISTS applicants_submission_key_idx
    ON public.applicants (submission_key) WHERE submission_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS applicants_normalized_email_idx
    ON public.applicants (LOWER(BTRIM(COALESCE(email, ''))));
CREATE INDEX IF NOT EXISTS employees_normalized_email_idx
    ON public.employees (LOWER(BTRIM(COALESCE(email, ''))));
CREATE INDEX IF NOT EXISTS users_normalized_email_idx
    ON public.users (LOWER(BTRIM(COALESCE(email, ''))));
CREATE INDEX IF NOT EXISTS applicants_normalized_name_idx
    ON public.applicants (LOWER(REGEXP_REPLACE(BTRIM(COALESCE(name, '')), '[[:space:]]+', ' ', 'g')));
CREATE INDEX IF NOT EXISTS employees_normalized_name_idx
    ON public.employees (LOWER(REGEXP_REPLACE(BTRIM(COALESCE(name, '')), '[[:space:]]+', ' ', 'g')));
-- Serialize only writes for the same normalized name. Hash collisions only serialize
-- extra names; they cannot bypass the cross-table uniqueness check.
CREATE OR REPLACE FUNCTION public.enforce_unique_person_name() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    normalized_name TEXT;
BEGIN
    normalized_name := LOWER(REGEXP_REPLACE(BTRIM(COALESCE(NEW.name, '')), '[[:space:]]+', ' ', 'g'));
    IF normalized_name = '' THEN
        RETURN NEW;
    END IF;

    PERFORM pg_advisory_xact_lock(19789, hashtext(normalized_name));

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


-- Install the same protection on deployments that missed the earlier name migration.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.applicants'::regclass AND tgname = 'applicants_unique_person_name_insert') THEN
        CREATE TRIGGER applicants_unique_person_name_insert BEFORE INSERT ON public.applicants
            FOR EACH ROW EXECUTE FUNCTION public.enforce_unique_person_name();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.applicants'::regclass AND tgname = 'applicants_unique_person_name_update') THEN
        CREATE TRIGGER applicants_unique_person_name_update BEFORE UPDATE OF name, email, status ON public.applicants
            FOR EACH ROW EXECUTE FUNCTION public.enforce_unique_person_name();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.employees'::regclass AND tgname = 'employees_unique_person_name_insert') THEN
        CREATE TRIGGER employees_unique_person_name_insert BEFORE INSERT ON public.employees
            FOR EACH ROW EXECUTE FUNCTION public.enforce_unique_person_name();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.employees'::regclass AND tgname = 'employees_unique_person_name_update') THEN
        CREATE TRIGGER employees_unique_person_name_update BEFORE UPDATE OF name, email ON public.employees
            FOR EACH ROW EXECUTE FUNCTION public.enforce_unique_person_name();
    END IF;
END;
$$;
COMMIT;
