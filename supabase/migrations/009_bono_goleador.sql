-- =====================================================================
-- QUINIELA MUNDIAL 2026 – La Corte
-- Migration: 009_bono_goleador.sql
--   · Nuevo tipo de folio "goleador": bono especial por consumo del día
--     4 niveles: $1,500=15pts · $2,500=30pts · $3,500=45pts · $5,000+=60pts
--   · Regla: 1 canje "goleador" por día por usuario (aunque haya 4 códigos)
--   · Vigencia: jueves 9/jul → domingo 19/jul 2026 (11 días de cierre)
-- =====================================================================

-- ─── 1. Columna puntos en codigos (puntos variables por folio) ─────
ALTER TABLE public.codigos
  ADD COLUMN IF NOT EXISTS puntos INT;

-- ─── 2. Insertar 44 folios "goleador" (11 días × 4 niveles) ───────
INSERT INTO public.codigos (code, tipo, fecha_valida, puntos) VALUES
-- Jue 9/7
('GOL1500-0907', 'goleador', '2026-07-09', 15),
('GOL2500-0907', 'goleador', '2026-07-09', 30),
('GOL3500-0907', 'goleador', '2026-07-09', 45),
('GOL5000-0907', 'goleador', '2026-07-09', 60),
-- Vie 10/7
('GOL1500-1007', 'goleador', '2026-07-10', 15),
('GOL2500-1007', 'goleador', '2026-07-10', 30),
('GOL3500-1007', 'goleador', '2026-07-10', 45),
('GOL5000-1007', 'goleador', '2026-07-10', 60),
-- Sáb 11/7
('GOL1500-1107', 'goleador', '2026-07-11', 15),
('GOL2500-1107', 'goleador', '2026-07-11', 30),
('GOL3500-1107', 'goleador', '2026-07-11', 45),
('GOL5000-1107', 'goleador', '2026-07-11', 60),
-- Dom 12/7
('GOL1500-1207', 'goleador', '2026-07-12', 15),
('GOL2500-1207', 'goleador', '2026-07-12', 30),
('GOL3500-1207', 'goleador', '2026-07-12', 45),
('GOL5000-1207', 'goleador', '2026-07-12', 60),
-- Lun 13/7
('GOL1500-1307', 'goleador', '2026-07-13', 15),
('GOL2500-1307', 'goleador', '2026-07-13', 30),
('GOL3500-1307', 'goleador', '2026-07-13', 45),
('GOL5000-1307', 'goleador', '2026-07-13', 60),
-- Mar 14/7 · Semifinal 1
('GOL1500-1407', 'goleador', '2026-07-14', 15),
('GOL2500-1407', 'goleador', '2026-07-14', 30),
('GOL3500-1407', 'goleador', '2026-07-14', 45),
('GOL5000-1407', 'goleador', '2026-07-14', 60),
-- Mié 15/7 · Semifinal 2
('GOL1500-1507', 'goleador', '2026-07-15', 15),
('GOL2500-1507', 'goleador', '2026-07-15', 30),
('GOL3500-1507', 'goleador', '2026-07-15', 45),
('GOL5000-1507', 'goleador', '2026-07-15', 60),
-- Jue 16/7
('GOL1500-1607', 'goleador', '2026-07-16', 15),
('GOL2500-1607', 'goleador', '2026-07-16', 30),
('GOL3500-1607', 'goleador', '2026-07-16', 45),
('GOL5000-1607', 'goleador', '2026-07-16', 60),
-- Vie 17/7
('GOL1500-1707', 'goleador', '2026-07-17', 15),
('GOL2500-1707', 'goleador', '2026-07-17', 30),
('GOL3500-1707', 'goleador', '2026-07-17', 45),
('GOL5000-1707', 'goleador', '2026-07-17', 60),
-- Sáb 18/7 · 3er lugar
('GOL1500-1807', 'goleador', '2026-07-18', 15),
('GOL2500-1807', 'goleador', '2026-07-18', 30),
('GOL3500-1807', 'goleador', '2026-07-18', 45),
('GOL5000-1807', 'goleador', '2026-07-18', 60),
-- Dom 19/7 · FINAL
('GOL1500-1907', 'goleador', '2026-07-19', 15),
('GOL2500-1907', 'goleador', '2026-07-19', 30),
('GOL3500-1907', 'goleador', '2026-07-19', 45),
('GOL5000-1907', 'goleador', '2026-07-19', 60)
ON CONFLICT (code) DO NOTHING;

-- ─── 3. RPC canjear_codigo: soportar tipo "goleador" + regla 1/día ─
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
  v_corte_lat  CONSTANT DOUBLE PRECISION :=  23.752555875229184;
  v_corte_lng  CONSTANT DOUBLE PRECISION := -99.14650964662673;
  v_radio_max  CONSTANT INT := 150;
  v_distancia  DOUBLE PRECISION;
  v_sospechoso BOOLEAN := FALSE;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'msg', 'No estás autenticado');
  END IF;

  -- ── Ubicación obligatoria ─────────────────────────────────
  IF p_lat IS NULL OR p_lng IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'msg', 'Activa la ubicación de tu celular para canjear el folio en La Corte 📍');
  END IF;

  -- ── Distancia (Haversine) ─────────────────────────────────
  v_distancia := 2 * 6371000 * asin(sqrt(
    power(sin(radians((p_lat - v_corte_lat) / 2)), 2) +
    cos(radians(v_corte_lat)) * cos(radians(p_lat)) *
    power(sin(radians((p_lng - v_corte_lng) / 2)), 2)
  ));

  IF v_distancia > v_radio_max THEN
    RETURN jsonb_build_object(
      'ok', false,
      'msg', 'Este folio solo se puede canjear estando en La Corte. Estás a ' || ROUND(v_distancia)::TEXT || 'm 🚫'
    );
  END IF;

  IF p_accuracy IS NOT NULL AND p_accuracy < 5 THEN
    v_sospechoso := TRUE;
  END IF;

  -- ── Regla especial GOLEADOR: solo 1 por día por usuario ──
  IF p_tipo = 'goleador' THEN
    IF EXISTS (
      SELECT 1
      FROM codigos_canjeados cc
      JOIN codigos c ON c.code = cc.code
      WHERE cc.user_id = v_user_id
        AND c.tipo = 'goleador'
        AND (cc.redeemed_at AT TIME ZONE 'America/Mexico_City')::DATE = v_today
    ) THEN
      RETURN jsonb_build_object('ok', false, 'msg', 'Ya usaste tu Bono Goleador de hoy 🥅 Regresa mañana');
    END IF;
  END IF;

  -- ── Buscar el folio ───────────────────────────────────────
  SELECT code, tipo, fecha_valida, puntos INTO v_code
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

  -- ── Calcular puntos según tipo ────────────────────────────
  v_pts := CASE
    WHEN p_tipo = 'goleador' THEN COALESCE(v_code.puntos, 0)
    WHEN p_tipo = 'consumo'  THEN 20
    ELSE 15
  END;

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
    'ok',  true,
    'msg', '+' || v_pts || ' puntos por ' ||
           CASE p_tipo
             WHEN 'goleador' THEN 'Bono Goleador 🥅'
             WHEN 'consumo'  THEN 'consumo 🍔'
             ELSE 'visita 🏠'
           END || ' ✅',
    'dist', ROUND(v_distancia)::INT
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.canjear_codigo(
  TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION
) TO authenticated;

-- ─── 4. Refrescar schema cache ─────────────────────────────
NOTIFY pgrst, 'reload schema';
