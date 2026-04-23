-- =====================================================================
-- QUINIELA MUNDIAL 2026 – La Corte
-- Migration: 002_username_password.sql
--   · Agrega columna username a profiles (único, case-insensitive)
--   · Funciones RPC para registro/login por nombre de usuario
-- =====================================================================

-- ─── Columna username ──────────────────────────────────────────────
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS username TEXT;

-- Unicidad case-insensitive (permite NULL para perfiles antiguos)
CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_lower_uniq
  ON profiles (LOWER(username))
  WHERE username IS NOT NULL;

-- ─── RPC: ¿el username ya está tomado? ─────────────────────────────
-- SECURITY DEFINER para que anon pueda consultar sin leer la tabla.
CREATE OR REPLACE FUNCTION username_taken(p_username TEXT)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles
    WHERE LOWER(username) = LOWER(p_username)
  );
$$;

GRANT EXECUTE ON FUNCTION username_taken(TEXT) TO anon, authenticated;

-- ─── RPC: devolver email asociado a un username (para login) ───────
-- Evita exponer la tabla profiles.email al público.
CREATE OR REPLACE FUNCTION email_for_username(p_username TEXT)
RETURNS TEXT
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  SELECT email FROM profiles
  WHERE LOWER(username) = LOWER(p_username)
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION email_for_username(TEXT) TO anon, authenticated;
