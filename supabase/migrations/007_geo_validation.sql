-- =====================================================================
-- QUINIELA MUNDIAL 2026 – La Corte
-- Migration: 007_geo_validation.sql
--   · canjear_codigo ahora valida que el cliente esté FÍSICAMENTE en
--     La Corte (radio de 150m alrededor de las coordenadas oficiales)
--   · Guarda lat/lng de cada canje en codigos_canjeados (auditoría)
--   · Bandera anti-spoofing: si la precisión es sospechosamente perfecta
--     (<5m), marca el canje como "revisar"
-- =====================================================================

-- ─── 1. Columnas de auditoría en codigos_canjeados ────────────────
ALTER TABLE public.codigos_canjeados
  ADD COLUMN IF NOT EXISTS canje_lat       DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS canje_lng       DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS canje_accuracy  DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS canje_distancia DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS canje_sospechoso BOOLEAN DEFAULT FALSE;

-- ─── 2. RPC: canjear_codigo con validación de ubicación ─────────
DROP FUNCTION IF EXISTS public.canjear_codigo(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.canjear_codigo(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION);

CREATE OR REPLACE FUNCTION public.canjear_codigo(
  p_code     TEXT,
  p_tipo     TEXT,
  p_lat      DOUBLE PRECISION DEFAULT NULL,
  p_lng      DOUBLE PRECISION DEFAULT NULL,
  p_accuracy DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_user_id    UUID := auth.uid();
  v_code       RECORD;
  v_today      DATE := (NOW() AT TIME ZONE 'America/Mexico_City')::DATE;
  v_pts        INT;
  -- Coordenadas oficiales de La Corte Restaurante (Ciudad Victoria, Tamps.)
  v_corte_lat  CONSTANT DOUBLE PRECISION :=  23.752555875229184;
  v_corte_lng  CONSTANT DOUBLE PRECISION := -99.14650964662673;
  -- Radio aceptado en metros (cubre comedor + terraza + estacionamiento)
  v_radio_max  CONSTANT INT := 150;
  v_distancia  DOUBLE PRECISION;
  v_sospechoso BOOLEAN := FALSE;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'msg', 'No estás autenticado');
  END IF;

  -- ── Validar ubicación obligatoriamente ──────────────────────
  IF p_lat IS NULL OR p_lng IS NULL THEN
    RETURN jsonb_build_object(
      'ok',  false,
      'msg', 'Activa la ubicación de tu celular para canjear el folio en La Corte 📍'
    );
  END IF;

  -- ── Calcular distancia (Haversine) ─────────────────────────
  v_distancia := 2 * 6371000 * asin(sqrt(
    power(sin(radians((p_lat - v_corte_lat) / 2)), 2) +
    cos(radians(v_corte_lat)) * cos(radians(p_lat)) *
    power(sin(radians((p_lng - v_corte_lng) / 2)), 2)
  ));

  IF v_distancia > v_radio_max THEN
    RETURN jsonb_build_object(
      'ok',  false,
      'msg', 'Este folio solo se puede canjear estando en La Corte. Estás a ' ||
             ROUND(v_distancia)::TEXT || 'm 🚫'
    );
  END IF;

  -- ── Bandera anti-spoofing: precisión "demasiado perfecta" ──
  IF p_accuracy IS NOT NULL AND p_accuracy < 5 THEN
    v_sospechoso := TRUE;
  END IF;

  -- ── Validar el folio ────────────────────────────────────────
  SELECT code, tipo, fecha_valida INTO v_code
  FROM codigos
  WHERE UPPER(code) = UPPER(p_code) AND tipo = p_tipo;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'msg', 'Código no válido o tipo equivocado');
  END IF;

  IF v_code.fecha_valida <> v_today THEN
    RETURN jsonb_build_object(
      'ok',  false,
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

  INSERT INTO codigos_canjeados (
    code, user_id, canje_lat, canje_lng, canje_accuracy,
    canje_distancia, canje_sospechoso
  ) VALUES (
    v_code.code, v_user_id, p_lat, p_lng, p_accuracy,
    v_distancia, v_sospechoso
  );

  UPDATE profiles
    SET puntos_codigos = COALESCE(puntos_codigos, 0) + v_pts
    WHERE id = v_user_id;

  RETURN jsonb_build_object(
    'ok',   true,
    'msg',  '+' || v_pts || ' puntos por ' || p_tipo || ' ✅',
    'dist', ROUND(v_distancia)::INT
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.canjear_codigo(
  TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION
) TO authenticated;

-- ─── 3. Refrescar schema cache ─────────────────────────────────────
NOTIFY pgrst, 'reload schema';
