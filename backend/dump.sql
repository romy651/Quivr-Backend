

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


CREATE EXTENSION IF NOT EXISTS "pgsodium" WITH SCHEMA "pgsodium";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE SCHEMA IF NOT EXISTS "stripe";


ALTER SCHEMA "stripe" OWNER TO "postgres";


CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "vector" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "wrappers" WITH SCHEMA "public";






CREATE TYPE "public"."brain_tags" AS ENUM (
    'new',
    'recommended',
    'most_popular',
    'premium',
    'coming_soon',
    'community',
    'deprecated'
);


ALTER TYPE "public"."brain_tags" OWNER TO "postgres";


CREATE TYPE "public"."brain_type_enum" AS ENUM (
    'doc',
    'api',
    'composite',
    'integration'
);


ALTER TYPE "public"."brain_type_enum" OWNER TO "postgres";


CREATE TYPE "public"."integration_type" AS ENUM (
    'custom',
    'sync',
    'doc'
);


ALTER TYPE "public"."integration_type" OWNER TO "postgres";


CREATE TYPE "public"."status" AS ENUM (
    'info',
    'warning',
    'success',
    'error'
);


ALTER TYPE "public"."status" OWNER TO "postgres";


CREATE TYPE "public"."tags" AS ENUM (
    'Finance',
    'Legal',
    'Health',
    'Technology',
    'Education',
    'Resources',
    'Marketing',
    'Strategy',
    'Operations',
    'Compliance',
    'Research',
    'Innovation',
    'Sustainability',
    'Management',
    'Communication',
    'Data',
    'Quality',
    'Logistics',
    'Policy',
    'Design',
    'Safety',
    'Customer',
    'Development',
    'Reporting',
    'Collaboration'
);


ALTER TYPE "public"."tags" OWNER TO "postgres";


CREATE TYPE "public"."thumbs" AS ENUM (
    'up',
    'down'
);


ALTER TYPE "public"."thumbs" OWNER TO "postgres";


CREATE TYPE "public"."user_identity_company_size" AS ENUM (
    '1-10',
    '10-25',
    '25-50',
    '50-100',
    '100-250',
    '250-500',
    '500-1000',
    '1000-5000',
    '+5000'
);


ALTER TYPE "public"."user_identity_company_size" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_secret"("secret_name" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
 deleted_rows int;
begin
 delete from vault.decrypted_secrets where name = secret_name;
 get diagnostics deleted_rows = row_count;
 if deleted_rows = 0 then
   return false;
 else
   return true;
 end if;
end;
$$;


ALTER FUNCTION "public"."delete_secret"("secret_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_email_by_user_id"("user_id" "uuid") RETURNS TABLE("email" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY SELECT au.email::text FROM auth.users au WHERE au.id = user_id;
END;
$$;


ALTER FUNCTION "public"."get_user_email_by_user_id"("user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_id_by_user_email"("user_email" "text") RETURNS TABLE("user_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY SELECT au.id::uuid FROM auth.users au WHERE au.email = user_email;
END;
$$;


ALTER FUNCTION "public"."get_user_id_by_user_email"("user_email" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO public.users (id, email)
  VALUES (NEW.id, NEW.email);
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."insert_secret"("name" "text", "secret" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  return vault.create_secret(secret, name);
end;
$$;


ALTER FUNCTION "public"."insert_secret"("name" "text", "secret" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_parent_folder"("folder_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$ BEGIN RETURN (
    SELECT k.is_folder
    FROM public.knowledge k
    WHERE k.id = folder_id
);
END;
$$;


ALTER FUNCTION "public"."is_parent_folder"("folder_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."match_brain"("query_embedding" "public"."vector", "match_count" integer, "p_user_id" "uuid") RETURNS TABLE("id" "uuid", "name" "text", "similarity" double precision)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    b.brain_id,
    b.name,
    1 - (b.meaning <=> query_embedding) as similarity
  FROM
    brains b
  LEFT JOIN
    brains_users bu ON b.brain_id = bu.brain_id
  WHERE
    (bu.user_id = p_user_id AND bu.rights IN ('Owner', 'Editor', 'Viewer'))
  ORDER BY
    b.meaning <=> query_embedding
  LIMIT
    match_count;
END;
$$;


ALTER FUNCTION "public"."match_brain"("query_embedding" "public"."vector", "match_count" integer, "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."match_vectors"("query_embedding" "public"."vector", "p_brain_id" "uuid", "max_chunk_sum" integer) RETURNS TABLE("id" "uuid", "brain_id" "uuid", "content" "text", "metadata" "jsonb", "embedding" "public"."vector", "similarity" double precision)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH ranked_vectors AS (
        SELECT
            v.id AS vector_id, -- Explicitly qualified
            bv.brain_id AS vector_brain_id, -- Explicitly qualified and aliased
            v.content AS vector_content, -- Explicitly qualified and aliased
            v.metadata AS vector_metadata, -- Explicitly qualified and aliased
            v.embedding AS vector_embedding, -- Explicitly qualified and aliased
            1 - (v.embedding <=> query_embedding) AS calculated_similarity, -- Calculated and aliased
            (v.metadata->>'chunk_size')::integer AS chunk_size -- Explicitly qualified
        FROM
            vectors v
        INNER JOIN
            brains_vectors bv ON v.id = bv.vector_id
        WHERE
            bv.brain_id = p_brain_id
        ORDER BY
            calculated_similarity -- Aliased similarity
    ), filtered_vectors AS (
        SELECT
            vector_id,
            vector_brain_id,
            vector_content,
            vector_metadata,
            vector_embedding,
            calculated_similarity,
            chunk_size,
            sum(chunk_size) OVER (ORDER BY calculated_similarity DESC) AS running_total
        FROM ranked_vectors
    )
    SELECT
        vector_id AS id,
        vector_brain_id AS brain_id,
        vector_content AS content,
        vector_metadata AS metadata,
        vector_embedding AS embedding,
        calculated_similarity AS similarity
    FROM filtered_vectors
    WHERE running_total <= max_chunk_sum;
END;
$$;


ALTER FUNCTION "public"."match_vectors"("query_embedding" "public"."vector", "p_brain_id" "uuid", "max_chunk_sum" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."read_secret"("secret_name" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  secret text;
begin
  select decrypted_secret from vault.decrypted_secrets where name =
  secret_name into secret;
  return secret;
end;
$$;


ALTER FUNCTION "public"."read_secret"("secret_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_max_brains_theodo"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    userEmail TEXT;
    allowedDomains TEXT[] := ARRAY['%@theodo.fr', '%@theodo.com', '%@theodo.co.uk', '%@bam.tech', '%@padok.fr', '%@aleios.com', '%@sicara.com', '%@hokla.com', '%@sipios.com'];
BEGIN
    SELECT email INTO userEmail FROM auth.users WHERE id = NEW.user_id;

    IF userEmail LIKE ANY(allowedDomains) THEN
        -- Ensure the models column is initialized as an array if null
        IF NEW.models IS NULL THEN
            NEW.models := '[]'::jsonb;
        END IF;

        -- Add gpt-4 if not present
        IF NOT NEW.models ? 'gpt-4' THEN
            NEW.models := NEW.models || '["gpt-4"]'::jsonb;
        END IF;

        -- Add gpt-3.5-turbo if not present
        IF NOT NEW.models ? 'gpt-3.5-turbo-1106' THEN
            NEW.models := NEW.models || '["gpt-3.5-turbo"]'::jsonb;
        END IF;

        UPDATE user_settings
        SET
            max_brains = 30,
            max_brain_size = 100000000,
            daily_chat_credit = 200,
            models = NEW.models
        WHERE user_id = NEW.user_id;
    END IF;

    RETURN NULL;  -- for AFTER triggers, the return value is ignored
END;
$$;


ALTER FUNCTION "public"."update_max_brains_theodo"() OWNER TO "postgres";


CREATE FOREIGN DATA WRAPPER "stripe_wrapper" HANDLER "public"."stripe_fdw_handler";




CREATE SERVER "stripe_server" FOREIGN DATA WRAPPER "stripe_wrapper" OPTIONS (
    "api_key" 'sk_test_51NtDTIJglvQxkJ1HVZHZHpKNAm48jAzKfJs93MjpKiML9YHy8G1YoKIf6SpcnGwRFWjmdS664A2Z2dn4LORWpo1P00qt6Jmy8G'
);


ALTER SERVER "stripe_server" OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."api_brain_definition" (
    "brain_id" "uuid" NOT NULL,
    "method" character varying(255),
    "url" character varying(255),
    "params" "json",
    "search_params" "json",
    "secrets" "json",
    "jq_instructions" "text" DEFAULT ''::"text" NOT NULL,
    "raw" boolean DEFAULT false NOT NULL,
    CONSTRAINT "api_brain_definition_method_check" CHECK ((("method")::"text" = ANY (ARRAY[('GET'::character varying)::"text", ('POST'::character varying)::"text", ('PUT'::character varying)::"text", ('DELETE'::character varying)::"text"])))
);


ALTER TABLE "public"."api_brain_definition" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."api_keys" (
    "key_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "api_key" "text",
    "creation_time" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "deleted_time" timestamp without time zone,
    "is_active" boolean DEFAULT true,
    "name" "text" DEFAULT 'API_KEY'::"text",
    "days" integer DEFAULT 30,
    "only_chat" boolean DEFAULT false
);


ALTER TABLE "public"."api_keys" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."assistants" (
    "name" "text",
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "brain_id_required" boolean DEFAULT true NOT NULL,
    "file_1_required" boolean DEFAULT false NOT NULL,
    "url_required" boolean DEFAULT false
);


ALTER TABLE "public"."assistants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."brain_subscription_invitations" (
    "brain_id" "uuid" NOT NULL,
    "email" character varying(255) NOT NULL,
    "rights" character varying(255)
);


ALTER TABLE "public"."brain_subscription_invitations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."brains" (
    "brain_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text",
    "status" "text" DEFAULT 'private'::"text",
    "model" "text" DEFAULT 'gpt-3.5-turbo-1106'::"text",
    "max_tokens" integer,
    "temperature" double precision,
    "description" "text" DEFAULT 'This needs to be changed'::"text" NOT NULL,
    "prompt_id" "uuid",
    "last_update" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "brain_type" "public"."brain_type_enum" DEFAULT 'doc'::"public"."brain_type_enum",
    "openai_api_key" "text",
    "meaning" "public"."vector",
    "tags" "public"."tags"[],
    "snippet_color" "text" DEFAULT '#d0c6f2'::"text" NOT NULL,
    "snippet_emoji" "text" DEFAULT '🧠'::"text" NOT NULL
);


ALTER TABLE "public"."brains" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."brains_users" (
    "brain_id" "uuid" NOT NULL,
    "rights" character varying(255),
    "default_brain" boolean DEFAULT false,
    "user_id" "uuid"
);


ALTER TABLE "public"."brains_users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."brains_vectors" (
    "brain_id" "uuid" NOT NULL,
    "file_sha1" "text",
    "vector_id" "uuid" NOT NULL,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL
);


ALTER TABLE "public"."brains_vectors" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_history" (
    "message_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "chat_id" "uuid" NOT NULL,
    "user_message" "text",
    "assistant" "text",
    "message_time" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "brain_id" "uuid",
    "prompt_id" "uuid",
    "metadata" "jsonb",
    "thumbs" boolean
);


ALTER TABLE "public"."chat_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chats" (
    "chat_id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid",
    "creation_time" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    "history" "jsonb",
    "chat_name" "text"
);


ALTER TABLE "public"."chats" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."composite_brain_connections" (
    "composite_brain_id" "uuid" NOT NULL,
    "connected_brain_id" "uuid" NOT NULL,
    CONSTRAINT "composite_brain_connections_check" CHECK (("composite_brain_id" <> "connected_brain_id"))
);


ALTER TABLE "public"."composite_brain_connections" OWNER TO "postgres";


CREATE FOREIGN TABLE "public"."customers" (
    "id" "text",
    "email" "text",
    "name" "text",
    "description" "text",
    "created" timestamp without time zone,
    "attrs" "jsonb"
)
SERVER "stripe_server"
OPTIONS (
    "object" 'customers',
    "rowid_column" 'id'
);


ALTER FOREIGN TABLE "public"."customers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."integrations" (
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "integration_name" "text" NOT NULL,
    "integration_logo_url" "text",
    "connection_settings" "jsonb",
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "description" "text" DEFAULT 'Default description'::"text" NOT NULL,
    "integration_type" "public"."integration_type" DEFAULT 'custom'::"public"."integration_type" NOT NULL,
    "max_files" integer DEFAULT 0 NOT NULL,
    "information" "text",
    "tags" "public"."brain_tags"[],
    "allow_model_change" boolean DEFAULT true NOT NULL,
    "integration_display_name" "text" DEFAULT 'Brain'::"text" NOT NULL,
    "onboarding_brain" boolean DEFAULT false
);


ALTER TABLE "public"."integrations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."integrations_user" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "brain_id" "uuid",
    "integration_id" "uuid",
    "settings" "jsonb",
    "credentials" "jsonb",
    "last_synced" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."integrations_user" OWNER TO "postgres";


ALTER TABLE "public"."integrations_user" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."integrations_user_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."knowledge" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "file_name" "text",
    "url" "text",
    "extension" "text" NOT NULL,
    "source" "text",
    "source_link" "text",
    "status" "text" DEFAULT 'UPLOADED'::"text" NOT NULL,
    "file_sha1" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "file_size" bigint,
    "metadata" "jsonb",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid",
    "is_folder" boolean DEFAULT false,
    "parent_id" "uuid",
    CONSTRAINT "check_parent_is_folder" CHECK ((("parent_id" IS NULL) OR "public"."is_parent_folder"("parent_id"))),
    CONSTRAINT "knowledge_check" CHECK (((("file_name" IS NOT NULL) AND ("url" IS NULL)) OR (("file_name" IS NULL) AND ("url" IS NOT NULL))))
);


ALTER TABLE "public"."knowledge" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."knowledge_brain" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "knowledge_id" "uuid",
    "brain_id" "uuid"
);


ALTER TABLE "public"."knowledge_brain" OWNER TO "postgres";


ALTER TABLE "public"."knowledge_brain" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."knowledge_brain_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."models" (
    "name" "text" NOT NULL,
    "price" integer DEFAULT 1,
    "max_input" integer DEFAULT 2000,
    "max_output" integer DEFAULT 1000,
    "description" "text" DEFAULT 'Default Description'::"text" NOT NULL,
    "display_name" "text" DEFAULT "gen_random_uuid"() NOT NULL,
    "image_url" "text" DEFAULT 'https://quivr-cms.s3.eu-west-3.amazonaws.com/logo_quivr_white_7e3c72620f.png'::"text" NOT NULL,
    "default" boolean DEFAULT false NOT NULL,
    "endpoint_url" "text" DEFAULT 'https://api.openai.com/v1'::"text" NOT NULL,
    "env_variable_name" "text" DEFAULT 'OPENAI_API_KEY'::"text" NOT NULL
);


ALTER TABLE "public"."models" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "datetime" timestamp with time zone DEFAULT ("now"() AT TIME ZONE 'utc'::"text"),
    "status" "public"."status" DEFAULT 'info'::"public"."status" NOT NULL,
    "archived" boolean DEFAULT false NOT NULL,
    "description" "text",
    "read" boolean DEFAULT false NOT NULL,
    "title" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "bulk_id" "uuid",
    "brain_id" "uuid",
    "category" "text"
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notion_sync" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "notion_id" "uuid" NOT NULL,
    "parent_id" "uuid",
    "is_folder" boolean,
    "icon" "text",
    "last_modified" timestamp with time zone,
    "web_view_link" "text",
    "type" "text",
    "name" "text",
    "mime_type" "text",
    "user_id" "text",
    "sync_user_id" bigint
);


ALTER TABLE "public"."notion_sync" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_to_features" (
    "id" bigint NOT NULL,
    "models" "jsonb" DEFAULT '["gpt-3.5-turbo-1106"]'::"jsonb" NOT NULL,
    "max_brains" integer NOT NULL,
    "max_brain_size" bigint DEFAULT '50000000'::bigint NOT NULL,
    "api_access" boolean DEFAULT false NOT NULL,
    "stripe_product_id" "text",
    "monthly_chat_credit" integer DEFAULT 20 NOT NULL,
    CONSTRAINT "product_to_features_max_brains_check" CHECK (("max_brains" > 0))
);


ALTER TABLE "public"."product_to_features" OWNER TO "postgres";


ALTER TABLE "public"."product_to_features" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."product_to_features_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE FOREIGN TABLE "public"."products" (
    "id" "text",
    "name" "text",
    "active" boolean,
    "default_price" "text",
    "description" "text",
    "created" timestamp without time zone,
    "updated" timestamp without time zone,
    "attrs" "jsonb"
)
SERVER "stripe_server"
OPTIONS (
    "object" 'products',
    "rowid_column" 'id'
);


ALTER FOREIGN TABLE "public"."products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prompts" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "title" character varying(255),
    "content" "text",
    "status" character varying(255) DEFAULT 'private'::character varying
);


ALTER TABLE "public"."prompts" OWNER TO "postgres";


CREATE FOREIGN TABLE "public"."subscriptions" (
    "id" "text",
    "customer" "text",
    "currency" "text",
    "current_period_start" timestamp without time zone,
    "current_period_end" timestamp without time zone,
    "attrs" "jsonb"
)
SERVER "stripe_server"
OPTIONS (
    "object" 'subscriptions',
    "rowid_column" 'id'
);


ALTER FOREIGN TABLE "public"."subscriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."syncs_active" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "syncs_user_id" bigint NOT NULL,
    "user_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "settings" "jsonb",
    "last_synced" timestamp with time zone DEFAULT '2024-06-01 15:30:25+00'::timestamp with time zone NOT NULL,
    "sync_interval_minutes" integer DEFAULT 360,
    "brain_id" "uuid",
    "force_sync" boolean DEFAULT false NOT NULL,
    "notification_id" "uuid"
);


ALTER TABLE "public"."syncs_active" OWNER TO "postgres";


ALTER TABLE "public"."syncs_active" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."syncs_active_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."syncs_files" (
    "id" bigint NOT NULL,
    "syncs_active_id" bigint NOT NULL,
    "last_modified" timestamp with time zone DEFAULT ("now"() AT TIME ZONE 'utc'::"text") NOT NULL,
    "brain_id" "uuid" DEFAULT "gen_random_uuid"(),
    "path" "text" NOT NULL,
    "supported" boolean DEFAULT true NOT NULL
);


ALTER TABLE "public"."syncs_files" OWNER TO "postgres";


ALTER TABLE "public"."syncs_files" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."syncs_files_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."syncs_user" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "provider" "text" NOT NULL,
    "state" "jsonb",
    "credentials" "jsonb",
    "user_id" "uuid" DEFAULT "gen_random_uuid"(),
    "email" "text",
    "additional_data" "jsonb" DEFAULT '{}'::"jsonb",
    "status" "text"
);


ALTER TABLE "public"."syncs_user" OWNER TO "postgres";


ALTER TABLE "public"."syncs_user" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."syncs_user_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."tasks" (
    "id" bigint NOT NULL,
    "pretty_id" "text",
    "user_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "status" "text",
    "creation_time" timestamp with time zone DEFAULT ("now"() AT TIME ZONE 'utc'::"text"),
    "answer" "text",
    "assistant_id" bigint NOT NULL,
    "settings" "jsonb"
);


ALTER TABLE "public"."tasks" OWNER TO "postgres";


ALTER TABLE "public"."tasks" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."tasks_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."user_daily_usage" (
    "user_id" "uuid" NOT NULL,
    "email" "text",
    "date" "text" NOT NULL,
    "daily_requests_count" integer
);


ALTER TABLE "public"."user_daily_usage" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_identity" (
    "user_id" "uuid" NOT NULL,
    "openai_api_key" character varying(255),
    "company" "text",
    "onboarded" boolean DEFAULT false NOT NULL,
    "username" "text",
    "company_size" "public"."user_identity_company_size",
    "usage_purpose" "text"
);


ALTER TABLE "public"."user_identity" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_settings" (
    "user_id" "uuid" NOT NULL,
    "max_brains" integer DEFAULT 3,
    "max_brain_size" bigint DEFAULT 50000000 NOT NULL,
    "is_premium" boolean DEFAULT false NOT NULL,
    "api_access" boolean DEFAULT false NOT NULL,
    "monthly_chat_credit" integer DEFAULT 100,
    "last_stripe_check" timestamp with time zone
);


ALTER TABLE "public"."user_settings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "email" "text",
    "onboarded" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."vectors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "content" "text",
    "metadata" "jsonb",
    "embedding" "public"."vector"(1536),
    "knowledge_id" "uuid"
);


ALTER TABLE "public"."vectors" OWNER TO "postgres";


ALTER TABLE ONLY "public"."api_brain_definition"
    ADD CONSTRAINT "api_brain_definition_pkey" PRIMARY KEY ("brain_id");



ALTER TABLE ONLY "public"."api_keys"
    ADD CONSTRAINT "api_keys_api_key_key" UNIQUE ("api_key");



ALTER TABLE ONLY "public"."api_keys"
    ADD CONSTRAINT "api_keys_pkey" PRIMARY KEY ("key_id");



ALTER TABLE ONLY "public"."brain_subscription_invitations"
    ADD CONSTRAINT "brain_subscription_invitations_pkey" PRIMARY KEY ("brain_id", "email");



ALTER TABLE ONLY "public"."brains"
    ADD CONSTRAINT "brains_pkey" PRIMARY KEY ("brain_id");



ALTER TABLE ONLY "public"."brains_vectors"
    ADD CONSTRAINT "brains_vectors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_history"
    ADD CONSTRAINT "chat_history_pkey" PRIMARY KEY ("chat_id", "message_id");



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_pkey" PRIMARY KEY ("chat_id");



ALTER TABLE ONLY "public"."composite_brain_connections"
    ADD CONSTRAINT "composite_brain_connections_pkey" PRIMARY KEY ("composite_brain_id", "connected_brain_id");



ALTER TABLE ONLY "public"."assistants"
    ADD CONSTRAINT "ingestions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."integrations"
    ADD CONSTRAINT "integrations_id_key" UNIQUE ("id");



ALTER TABLE ONLY "public"."integrations"
    ADD CONSTRAINT "integrations_integration_name_key" UNIQUE ("integration_name");



ALTER TABLE ONLY "public"."integrations"
    ADD CONSTRAINT "integrations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."integrations_user"
    ADD CONSTRAINT "integrations_user_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."knowledge_brain"
    ADD CONSTRAINT "knowledge_brain_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."knowledge"
    ADD CONSTRAINT "knowledge_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."models"
    ADD CONSTRAINT "models_pkey" PRIMARY KEY ("name");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notion_sync"
    ADD CONSTRAINT "notion_sync_notion_id_key" UNIQUE ("notion_id");



ALTER TABLE ONLY "public"."notion_sync"
    ADD CONSTRAINT "notion_sync_pkey" PRIMARY KEY ("id", "notion_id");



ALTER TABLE ONLY "public"."product_to_features"
    ADD CONSTRAINT "product_to_features_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prompts"
    ADD CONSTRAINT "prompts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."syncs_files"
    ADD CONSTRAINT "sync_files_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."syncs_active"
    ADD CONSTRAINT "syncs_active_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."syncs_user"
    ADD CONSTRAINT "syncs_user_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_daily_usage"
    ADD CONSTRAINT "user_daily_usage_pkey" PRIMARY KEY ("user_id", "date");



ALTER TABLE ONLY "public"."user_identity"
    ADD CONSTRAINT "user_identity_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."user_settings"
    ADD CONSTRAINT "user_settings_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."vectors"
    ADD CONSTRAINT "vectors_new_pkey" PRIMARY KEY ("id");



CREATE INDEX "brains_vectors_brain_id_idx" ON "public"."brains_vectors" USING "btree" ("brain_id");



CREATE INDEX "brains_vectors_vector_id_idx" ON "public"."brains_vectors" USING "btree" ("vector_id");



CREATE INDEX "idx_brains_vectors_vector_id" ON "public"."brains_vectors" USING "btree" ("vector_id");



CREATE INDEX "idx_vectors_id" ON "public"."vectors" USING "btree" ("id");



CREATE INDEX "knowledge_brain_brain_id_idx" ON "public"."knowledge_brain" USING "btree" ("brain_id");



CREATE INDEX "knowledge_brain_knowledge_id_idx" ON "public"."knowledge_brain" USING "btree" ("knowledge_id");



CREATE INDEX "knowledge_file_sha1_hash_idx" ON "public"."knowledge" USING "hash" ("file_sha1");



CREATE INDEX "knowledge_parent_id_idx" ON "public"."knowledge" USING "btree" ("parent_id");



CREATE INDEX "vectors_id_idx" ON "public"."vectors" USING "btree" ("id");



CREATE INDEX "vectors_knowledge_id_idx" ON "public"."vectors" USING "btree" ("knowledge_id");



CREATE INDEX "vectors_metadata_idx" ON "public"."vectors" USING "gin" ("metadata");



CREATE OR REPLACE TRIGGER "update_max_brains_theodo_trigger" AFTER INSERT ON "public"."user_settings" FOR EACH ROW EXECUTE FUNCTION "public"."update_max_brains_theodo"();



ALTER TABLE ONLY "public"."api_brain_definition"
    ADD CONSTRAINT "api_brain_definition_brain_id_fkey" FOREIGN KEY ("brain_id") REFERENCES "public"."brains"("brain_id");



ALTER TABLE ONLY "public"."api_keys"
    ADD CONSTRAINT "api_keys_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."brain_subscription_invitations"
    ADD CONSTRAINT "brain_subscription_invitations_brain_id_fkey" FOREIGN KEY ("brain_id") REFERENCES "public"."brains"("brain_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."brains"
    ADD CONSTRAINT "brains_prompt_id_fkey" FOREIGN KEY ("prompt_id") REFERENCES "public"."prompts"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."brains_users"
    ADD CONSTRAINT "brains_users_brain_id_fkey" FOREIGN KEY ("brain_id") REFERENCES "public"."brains"("brain_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."brains_users"
    ADD CONSTRAINT "brains_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."brains_vectors"
    ADD CONSTRAINT "brains_vectors_brain_id_fkey" FOREIGN KEY ("brain_id") REFERENCES "public"."brains"("brain_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."brains_vectors"
    ADD CONSTRAINT "brains_vectors_vector_id_fkey" FOREIGN KEY ("vector_id") REFERENCES "public"."vectors"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_history"
    ADD CONSTRAINT "chat_history_brain_id_fkey" FOREIGN KEY ("brain_id") REFERENCES "public"."brains"("brain_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_history"
    ADD CONSTRAINT "chat_history_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."chats"("chat_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_history"
    ADD CONSTRAINT "chat_history_prompt_id_fkey" FOREIGN KEY ("prompt_id") REFERENCES "public"."prompts"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."composite_brain_connections"
    ADD CONSTRAINT "composite_brain_connections_composite_brain_id_fkey" FOREIGN KEY ("composite_brain_id") REFERENCES "public"."brains"("brain_id");



ALTER TABLE ONLY "public"."composite_brain_connections"
    ADD CONSTRAINT "composite_brain_connections_connected_brain_id_fkey" FOREIGN KEY ("connected_brain_id") REFERENCES "public"."brains"("brain_id");



ALTER TABLE ONLY "public"."integrations_user"
    ADD CONSTRAINT "integrations_user_brain_id_fkey" FOREIGN KEY ("brain_id") REFERENCES "public"."brains"("brain_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."integrations_user"
    ADD CONSTRAINT "integrations_user_integration_id_fkey" FOREIGN KEY ("integration_id") REFERENCES "public"."integrations"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."integrations_user"
    ADD CONSTRAINT "integrations_user_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."knowledge_brain"
    ADD CONSTRAINT "public_knowledge_brain_brain_id_fkey" FOREIGN KEY ("brain_id") REFERENCES "public"."brains"("brain_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."knowledge_brain"
    ADD CONSTRAINT "public_knowledge_brain_knowledge_id_fkey" FOREIGN KEY ("knowledge_id") REFERENCES "public"."knowledge"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."knowledge"
    ADD CONSTRAINT "public_knowledge_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."knowledge"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."knowledge"
    ADD CONSTRAINT "public_knowledge_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "public_notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notion_sync"
    ADD CONSTRAINT "public_notion_sync_syncs_user_id_fkey" FOREIGN KEY ("sync_user_id") REFERENCES "public"."syncs_user"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."syncs_files"
    ADD CONSTRAINT "public_sync_files_brain_id_fkey" FOREIGN KEY ("brain_id") REFERENCES "public"."brains"("brain_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."syncs_files"
    ADD CONSTRAINT "public_sync_files_sync_active_id_fkey" FOREIGN KEY ("syncs_active_id") REFERENCES "public"."syncs_active"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."syncs_active"
    ADD CONSTRAINT "public_syncs_active_brain_id_fkey" FOREIGN KEY ("brain_id") REFERENCES "public"."brains"("brain_id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."syncs_active"
    ADD CONSTRAINT "public_syncs_active_syncs_user_id_fkey" FOREIGN KEY ("syncs_user_id") REFERENCES "public"."syncs_user"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."syncs_active"
    ADD CONSTRAINT "public_syncs_active_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."syncs_user"
    ADD CONSTRAINT "public_syncs_user_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_identity"
    ADD CONSTRAINT "public_user_identity_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."vectors"
    ADD CONSTRAINT "public_vectors_knowledge_id_fkey" FOREIGN KEY ("knowledge_id") REFERENCES "public"."knowledge"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tasks"
    ADD CONSTRAINT "tasks_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_daily_usage"
    ADD CONSTRAINT "user_daily_usage_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_settings"
    ADD CONSTRAINT "user_settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "API_BRAIN_DEFINITION" ON "public"."api_brain_definition" TO "service_role";



CREATE POLICY "API_KEYS" ON "public"."api_keys" TO "service_role";



CREATE POLICY "BRAINS" ON "public"."brains" TO "service_role";



CREATE POLICY "BRAINS_USERS" ON "public"."brains_users" TO "service_role";



CREATE POLICY "BRAINS_VECTORS" ON "public"."brains_vectors" TO "service_role";



CREATE POLICY "BRAIN_SUBSCRIPTION_INVITATIONS" ON "public"."brain_subscription_invitations" TO "service_role";



CREATE POLICY "CHATS" ON "public"."chats" TO "service_role";



CREATE POLICY "CHAT_HISTORY" ON "public"."chat_history" TO "service_role";



CREATE POLICY "COMPOSITE_BRAIN_CONNECTIONS" ON "public"."composite_brain_connections" TO "service_role";



CREATE POLICY "Enable all for service role" ON "public"."integrations_user" TO "service_role" WITH CHECK (true);



CREATE POLICY "INGESTION" ON "public"."assistants" TO "service_role";



CREATE POLICY "INTEGRATIONS" ON "public"."integrations" TO "service_role";



CREATE POLICY "KNOWLEDGE" ON "public"."knowledge" TO "service_role";



CREATE POLICY "MODELS" ON "public"."models" TO "service_role";



CREATE POLICY "NOTIFICATIONS" ON "public"."notifications" TO "service_role";



CREATE POLICY "PRODUCT_TO_FEATURES" ON "public"."product_to_features" TO "service_role";



CREATE POLICY "PROMPTS" ON "public"."prompts" TO "service_role";



CREATE POLICY "USERS" ON "public"."users";



CREATE POLICY "USER_DAILY_USAGE" ON "public"."user_daily_usage" TO "service_role";



CREATE POLICY "USER_IDENTITY" ON "public"."user_identity" TO "service_role";



CREATE POLICY "USER_SETTINGS" ON "public"."user_settings" TO "service_role";



CREATE POLICY "VECTORS" ON "public"."vectors" TO "service_role";



CREATE POLICY "allow_user_all_notifications" ON "public"."notifications" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "allow_user_all_syncs_user" ON "public"."syncs_user" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "allow_user_all_tasks" ON "public"."tasks" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "public"."api_brain_definition" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."api_keys" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."assistants" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."brain_subscription_invitations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."brains" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."brains_users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."brains_vectors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chat_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chats" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."composite_brain_connections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."integrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."integrations_user" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."knowledge" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."knowledge_brain" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."models" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notion_sync" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."product_to_features" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."prompts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."syncs_active" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "syncs_active" ON "public"."syncs_active" TO "service_role";



ALTER TABLE "public"."syncs_files" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."syncs_user" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "syncs_user" ON "public"."syncs_user" TO "service_role";



ALTER TABLE "public"."tasks" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tasks" ON "public"."tasks" TO "service_role";



ALTER TABLE "public"."user_daily_usage" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_identity" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_settings" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."vectors" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."notifications";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."syncs_user";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "service_role";




















































































































































































GRANT ALL ON FUNCTION "public"."airtable_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."airtable_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."airtable_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."airtable_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."airtable_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."airtable_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."airtable_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."airtable_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."airtable_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."airtable_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."airtable_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."airtable_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."auth0_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."auth0_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."auth0_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auth0_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auth0_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."auth0_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."auth0_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auth0_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auth0_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."auth0_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."auth0_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."auth0_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."big_query_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."big_query_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."big_query_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."big_query_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."big_query_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."big_query_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."big_query_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."big_query_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."big_query_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."big_query_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."big_query_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."big_query_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."click_house_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."click_house_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."click_house_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."click_house_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."click_house_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."click_house_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."click_house_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."click_house_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."click_house_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."click_house_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."click_house_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."click_house_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."cognito_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."cognito_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."cognito_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cognito_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cognito_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."cognito_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."cognito_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cognito_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cognito_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."cognito_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."cognito_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cognito_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_secret"("secret_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_secret"("secret_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_secret"("secret_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."firebase_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."firebase_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."firebase_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."firebase_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."firebase_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."firebase_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."firebase_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."firebase_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."firebase_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."firebase_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."firebase_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."firebase_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_email_by_user_id"("user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_email_by_user_id"("user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_email_by_user_id"("user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_id_by_user_email"("user_email" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_id_by_user_email"("user_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_id_by_user_email"("user_email" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "postgres";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "anon";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "authenticated";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."hello_world_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."hello_world_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."hello_world_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."insert_secret"("name" "text", "secret" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."insert_secret"("name" "text", "secret" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."insert_secret"("name" "text", "secret" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_parent_folder"("folder_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_parent_folder"("folder_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_parent_folder"("folder_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "postgres";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "anon";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "authenticated";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "service_role";



GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."logflare_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."logflare_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."logflare_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."logflare_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."logflare_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."logflare_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."logflare_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."logflare_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."logflare_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."logflare_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."logflare_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."logflare_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."match_brain"("query_embedding" "public"."vector", "match_count" integer, "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."match_brain"("query_embedding" "public"."vector", "match_count" integer, "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."match_brain"("query_embedding" "public"."vector", "match_count" integer, "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."match_vectors"("query_embedding" "public"."vector", "p_brain_id" "uuid", "max_chunk_sum" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."match_vectors"("query_embedding" "public"."vector", "p_brain_id" "uuid", "max_chunk_sum" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."match_vectors"("query_embedding" "public"."vector", "p_brain_id" "uuid", "max_chunk_sum" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."mssql_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."mssql_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."mssql_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."mssql_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mssql_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."mssql_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."mssql_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."mssql_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mssql_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."mssql_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."mssql_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mssql_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."read_secret"("secret_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."read_secret"("secret_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."read_secret"("secret_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."redis_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."redis_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."redis_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."redis_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."redis_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."redis_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."redis_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."redis_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."redis_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."redis_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."redis_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."redis_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."s3_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."s3_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."s3_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."s3_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."s3_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."s3_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."s3_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."s3_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."s3_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."s3_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."s3_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."s3_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."stripe_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."stripe_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."stripe_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."stripe_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."stripe_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."stripe_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."stripe_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."stripe_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."stripe_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."stripe_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."stripe_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."stripe_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_max_brains_theodo"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_max_brains_theodo"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_max_brains_theodo"() TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."wasm_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."wasm_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."wasm_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."wasm_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."wasm_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."wasm_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."wasm_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."wasm_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."wasm_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."wasm_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."wasm_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."wasm_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "service_role";


















GRANT ALL ON TABLE "public"."api_brain_definition" TO "anon";
GRANT ALL ON TABLE "public"."api_brain_definition" TO "authenticated";
GRANT ALL ON TABLE "public"."api_brain_definition" TO "service_role";



GRANT ALL ON TABLE "public"."api_keys" TO "anon";
GRANT ALL ON TABLE "public"."api_keys" TO "authenticated";
GRANT ALL ON TABLE "public"."api_keys" TO "service_role";



GRANT ALL ON TABLE "public"."assistants" TO "anon";
GRANT ALL ON TABLE "public"."assistants" TO "authenticated";
GRANT ALL ON TABLE "public"."assistants" TO "service_role";



GRANT ALL ON TABLE "public"."brain_subscription_invitations" TO "anon";
GRANT ALL ON TABLE "public"."brain_subscription_invitations" TO "authenticated";
GRANT ALL ON TABLE "public"."brain_subscription_invitations" TO "service_role";



GRANT ALL ON TABLE "public"."brains" TO "anon";
GRANT ALL ON TABLE "public"."brains" TO "authenticated";
GRANT ALL ON TABLE "public"."brains" TO "service_role";



GRANT ALL ON TABLE "public"."brains_users" TO "anon";
GRANT ALL ON TABLE "public"."brains_users" TO "authenticated";
GRANT ALL ON TABLE "public"."brains_users" TO "service_role";



GRANT ALL ON TABLE "public"."brains_vectors" TO "anon";
GRANT ALL ON TABLE "public"."brains_vectors" TO "authenticated";
GRANT ALL ON TABLE "public"."brains_vectors" TO "service_role";



GRANT ALL ON TABLE "public"."chat_history" TO "anon";
GRANT ALL ON TABLE "public"."chat_history" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_history" TO "service_role";



GRANT ALL ON TABLE "public"."chats" TO "anon";
GRANT ALL ON TABLE "public"."chats" TO "authenticated";
GRANT ALL ON TABLE "public"."chats" TO "service_role";



GRANT ALL ON TABLE "public"."composite_brain_connections" TO "anon";
GRANT ALL ON TABLE "public"."composite_brain_connections" TO "authenticated";
GRANT ALL ON TABLE "public"."composite_brain_connections" TO "service_role";



GRANT ALL ON TABLE "public"."customers" TO "anon";
GRANT ALL ON TABLE "public"."customers" TO "authenticated";
GRANT ALL ON TABLE "public"."customers" TO "service_role";



GRANT ALL ON TABLE "public"."integrations" TO "anon";
GRANT ALL ON TABLE "public"."integrations" TO "authenticated";
GRANT ALL ON TABLE "public"."integrations" TO "service_role";



GRANT ALL ON TABLE "public"."integrations_user" TO "anon";
GRANT ALL ON TABLE "public"."integrations_user" TO "authenticated";
GRANT ALL ON TABLE "public"."integrations_user" TO "service_role";



GRANT ALL ON SEQUENCE "public"."integrations_user_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."integrations_user_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."integrations_user_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."knowledge" TO "anon";
GRANT ALL ON TABLE "public"."knowledge" TO "authenticated";
GRANT ALL ON TABLE "public"."knowledge" TO "service_role";



GRANT ALL ON TABLE "public"."knowledge_brain" TO "anon";
GRANT ALL ON TABLE "public"."knowledge_brain" TO "authenticated";
GRANT ALL ON TABLE "public"."knowledge_brain" TO "service_role";



GRANT ALL ON SEQUENCE "public"."knowledge_brain_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."knowledge_brain_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."knowledge_brain_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."models" TO "anon";
GRANT ALL ON TABLE "public"."models" TO "authenticated";
GRANT ALL ON TABLE "public"."models" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."notion_sync" TO "anon";
GRANT ALL ON TABLE "public"."notion_sync" TO "authenticated";
GRANT ALL ON TABLE "public"."notion_sync" TO "service_role";



GRANT ALL ON TABLE "public"."product_to_features" TO "anon";
GRANT ALL ON TABLE "public"."product_to_features" TO "authenticated";
GRANT ALL ON TABLE "public"."product_to_features" TO "service_role";



GRANT ALL ON SEQUENCE "public"."product_to_features_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."product_to_features_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."product_to_features_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON TABLE "public"."prompts" TO "anon";
GRANT ALL ON TABLE "public"."prompts" TO "authenticated";
GRANT ALL ON TABLE "public"."prompts" TO "service_role";



GRANT ALL ON TABLE "public"."subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."subscriptions" TO "service_role";



GRANT ALL ON TABLE "public"."syncs_active" TO "anon";
GRANT ALL ON TABLE "public"."syncs_active" TO "authenticated";
GRANT ALL ON TABLE "public"."syncs_active" TO "service_role";



GRANT ALL ON SEQUENCE "public"."syncs_active_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."syncs_active_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."syncs_active_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."syncs_files" TO "anon";
GRANT ALL ON TABLE "public"."syncs_files" TO "authenticated";
GRANT ALL ON TABLE "public"."syncs_files" TO "service_role";



GRANT ALL ON SEQUENCE "public"."syncs_files_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."syncs_files_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."syncs_files_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."syncs_user" TO "anon";
GRANT ALL ON TABLE "public"."syncs_user" TO "authenticated";
GRANT ALL ON TABLE "public"."syncs_user" TO "service_role";



GRANT ALL ON SEQUENCE "public"."syncs_user_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."syncs_user_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."syncs_user_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."tasks" TO "anon";
GRANT ALL ON TABLE "public"."tasks" TO "authenticated";
GRANT ALL ON TABLE "public"."tasks" TO "service_role";



GRANT ALL ON SEQUENCE "public"."tasks_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."tasks_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."tasks_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."user_daily_usage" TO "anon";
GRANT ALL ON TABLE "public"."user_daily_usage" TO "authenticated";
GRANT ALL ON TABLE "public"."user_daily_usage" TO "service_role";



GRANT ALL ON TABLE "public"."user_identity" TO "anon";
GRANT ALL ON TABLE "public"."user_identity" TO "authenticated";
GRANT ALL ON TABLE "public"."user_identity" TO "service_role";



GRANT ALL ON TABLE "public"."user_settings" TO "anon";
GRANT ALL ON TABLE "public"."user_settings" TO "authenticated";
GRANT ALL ON TABLE "public"."user_settings" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT ALL ON TABLE "public"."vectors" TO "anon";
GRANT ALL ON TABLE "public"."vectors" TO "authenticated";
GRANT ALL ON TABLE "public"."vectors" TO "service_role";



GRANT ALL ON TABLE "public"."wrappers_fdw_stats" TO "postgres";
GRANT ALL ON TABLE "public"."wrappers_fdw_stats" TO "anon";
GRANT ALL ON TABLE "public"."wrappers_fdw_stats" TO "authenticated";
GRANT ALL ON TABLE "public"."wrappers_fdw_stats" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";






























RESET ALL;
