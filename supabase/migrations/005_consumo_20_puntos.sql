-- =====================================================================
-- QUINIELA MUNDIAL 2026 – La Corte
-- Migration: 005_consumo_20_puntos.sql
--   · CONSUMO ahora otorga 20 puntos (antes 15)
--   · VISITA sigue otorgando 15 puntos
-- =====================================================================

CREATE OR REPLACE FUNCTION public.canjear_codigo(p_code TEXT, p_tipo TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_code    RECORD;
  v_today   DATE := (NOW() AT TIME ZONE 'America/Mexico_City')::DATE;
  v_pts     INT;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'msg', 'No estás autenticado');
  END IF;

  SELECT code, tipo, fecha_valida INTO v_code
  FROM codigos
  WHERE UPPER(code) = UPPER(p_code) AND tipo = p_tipo;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'msg', 'Código no válido o tipo equivocado');
  END IF;

  IF v_code.fecha_valida <> v_today THEN
    RETURN jsonb_build_object(
      'ok', false,
      'msg', 'Este folio solo es válido el ' || TO_CHAR(v_code.fecha_valida, 'DD/MM/YYYY')
    );
  END IF;

  IF EXISTS (
    SELECT 1 FROM codigos_canjeados
    WHERE code = v_code.code AND user_id = v_user_id
  ) THEN
    RETURN jsonb_build_object('ok', false, 'msg', 'Ya canjeaste este folio');
  END IF;

  v_pts := CASE WHEN p_tipo = 'consumo' THEN 20 ELSE 15 END;

  INSERT INTO codigos_canjeados (code, user_id) VALUES (v_code.code, v_user_id);
  UPDATE profiles
    SET puntos_codigos = COALESCE(puntos_codigos, 0) + v_pts
    WHERE id = v_user_id;

  RETURN jsonb_build_object('ok', true, 'msg', '+' || v_pts || ' puntos por ' || p_tipo || ' ✅');
END;
$$;

GRANT EXECUTE ON FUNCTION public.canjear_codigo(TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
