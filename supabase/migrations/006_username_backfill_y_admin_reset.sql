-- =====================================================================
-- QUINIELA MUNDIAL 2026 – La Corte
-- Migration: 006_username_backfill_y_admin_reset.sql
--   · Backfill: usernames para perfiles antiguos sin uno (login por usuario)
--   · RPC admin_reset_user_points: admin puede resetear puntos de un usuario
-- =====================================================================

-- ─── 1. Backfill de usernames para perfiles antiguos ───────────────
-- Los usuarios creados vía OTP (antes del sistema usuario+contraseña)
-- tienen username = NULL y por eso no pueden entrar con nombre de usuario.
-- Asignamos el prefijo del correo, evitando duplicados.

UPDATE public.profiles
SET username = LOWER(split_part(email, '@', 1))
WHERE (username IS NULL OR username = '')
  AND NOT EXISTS (
    SELECT 1 FROM public.profiles p2
    WHERE LOWER(p2.username) = LOWER(split_part(profiles.email, '@', 1))
      AND p2.id <> profiles.id
  );

-- Para los que aún quedan NULL (porque hubo conflicto), usar email_prefix + 4 chars del id
UPDATE public.profiles
SET username = LOWER(split_part(email, '@', 1)) || substr(replace(id::text, '-', ''), 1, 4)
WHERE username IS NULL OR username = '';

-- ─── 2. RPC: admin resetea puntos + canjes de un usuario ───────────
CREATE OR REPLACE FUNCTION public.admin_reset_user_points(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller_role TEXT;
BEGIN
  SELECT role INTO v_caller_role
    FROM profiles WHERE id = auth.uid();

  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin','manager') THEN
    RETURN jsonb_build_object('ok', false, 'msg', 'Sin permiso (solo admin/manager)');
  END IF;

  DELETE FROM codigos_canjeados WHERE user_id = p_user_id;
  UPDATE profiles
    SET puntos_codigos = 0
    WHERE id = p_user_id;

  RETURN jsonb_build_object('ok', true, 'msg', 'Puntos y canjes reiniciados');
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_reset_user_points(UUID) TO authenticated;

-- ─── 3. Refrescar schema cache ─────────────────────────────────────
NOTIFY pgrst, 'reload schema';
