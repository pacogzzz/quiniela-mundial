-- =====================================================================
-- QUINIELA MUNDIAL 2026 – La Corte
-- Migration: 003_ranking_and_lock.sql
--   · Trigger: cada usuario nuevo en auth.users crea automáticamente
--     su fila en profiles (resuelve "usuarios que no aparecen en ranking")
--   · Backfill para usuarios ya existentes sin profile
--   · Trigger: bloquea INSERT/UPDATE de predicciones cuando el partido
--     ya empezó (fix: "puedes seguir editando después de iniciado")
--   · Vista/policy para listar usuarios en ADMIN
-- =====================================================================

-- ─── 1. Trigger: nuevo user en auth.users → profile automático ─────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, nombre, email, tel, username)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'nombre', split_part(NEW.email,'@',1)),
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'tel', ''),
    NEW.raw_user_meta_data->>'username'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ─── 2. Backfill: crea profile para cualquier auth.user sin uno ────
INSERT INTO public.profiles (id, nombre, email, tel)
SELECT
  u.id,
  COALESCE(u.raw_user_meta_data->>'nombre', split_part(u.email,'@',1)),
  u.email,
  COALESCE(u.raw_user_meta_data->>'tel', '')
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE p.id IS NULL;

-- ─── 3. Trigger: lock predicciones cuando el partido ya empezó ─────
CREATE OR REPLACE FUNCTION public.lock_predicciones_after_start()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  match_start TIMESTAMPTZ;
BEGIN
  SELECT date INTO match_start FROM public.matches WHERE id = NEW.match_id;
  IF match_start IS NULL THEN
    RAISE EXCEPTION 'Partido no existe';
  END IF;
  IF match_start <= NOW() THEN
    RAISE EXCEPTION 'El partido ya empezó — no se puede editar la predicción';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lock_predicciones_ins ON public.predicciones;
CREATE TRIGGER trg_lock_predicciones_ins
  BEFORE INSERT ON public.predicciones
  FOR EACH ROW EXECUTE FUNCTION public.lock_predicciones_after_start();

DROP TRIGGER IF EXISTS trg_lock_predicciones_upd ON public.predicciones;
CREATE TRIGGER trg_lock_predicciones_upd
  BEFORE UPDATE ON public.predicciones
  FOR EACH ROW EXECUTE FUNCTION public.lock_predicciones_after_start();

-- ─── 4. Asegurar que admin/manager pueden listar TODOS los perfiles
-- (la policy original ya permite "anyone authenticated can read",
--  pero lo reforzamos por claridad y dejamos listo el caso anónimo
--  si algún día se quiere un ranking público)
-- No se agregan policies extra — la vista `ranking` sigue funcionando
-- porque ahora TODOS los auth.users tendrán profile (vía trigger + backfill).
