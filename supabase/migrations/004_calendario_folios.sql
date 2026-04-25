-- =====================================================================
-- QUINIELA MUNDIAL 2026 – La Corte
-- Migration: 004_calendario_folios.sql
--   · 39 folios VISITA + 39 folios CONSUMO (uno por día del Mundial)
--   · Cada folio es válido SOLO en su fecha asignada
--   · Cada folio puede canjearse UNA SOLA VEZ POR USUARIO
-- =====================================================================

-- ─── 1. Nuevo esquema de codigos ───────────────────────────────────
ALTER TABLE public.codigos
  ADD COLUMN IF NOT EXISTS fecha_valida DATE;

-- Quitamos el modelo "un solo canje global" — ahora es por usuario
ALTER TABLE public.codigos DROP COLUMN IF EXISTS usado;
ALTER TABLE public.codigos DROP COLUMN IF EXISTS por_user_id;

-- ─── 2. Tabla de canjes (una fila por usuario × código) ───────────
CREATE TABLE IF NOT EXISTS public.codigos_canjeados (
  code         TEXT NOT NULL REFERENCES public.codigos(code) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  redeemed_at  TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (code, user_id)
);
ALTER TABLE public.codigos_canjeados ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "canjeados read all auth" ON public.codigos_canjeados;
CREATE POLICY "canjeados read all auth" ON public.codigos_canjeados
  FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "canjeados insert own" ON public.codigos_canjeados;
CREATE POLICY "canjeados insert own" ON public.codigos_canjeados
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ─── 3. Borrar todos los códigos viejos ────────────────────────────
TRUNCATE public.codigos_canjeados;
DELETE FROM public.codigos;

-- ─── 4. Insertar 39 + 39 folios fijos del Mundial 2026 ─────────────
-- Mundial: 11 jun 2026 → 19 jul 2026 (39 días)
INSERT INTO public.codigos (code, tipo, fecha_valida) VALUES
-- VISITA (uno por día)
('INAUGURA2026',     'visita',  '2026-06-11'),
('SILBATAZO',        'visita',  '2026-06-12'),
('PASIONLATINA',     'visita',  '2026-06-13'),
('RUGECORTE',        'visita',  '2026-06-14'),
('VIVELOMUNDIAL',    'visita',  '2026-06-15'),
('CHARROAZTECA',     'visita',  '2026-06-16'),
('ECOLATIDO',        'visita',  '2026-06-17'),
('BANDERAARRIBA',    'visita',  '2026-06-18'),
('ALMATRICOLOR',     'visita',  '2026-06-19'),
('CORAZONVERDE',     'visita',  '2026-06-20'),
('GRITOMUNDIAL',     'visita',  '2026-06-21'),
('EUFORIAGOL',       'visita',  '2026-06-22'),
('ESCUDOAZTECA',     'visita',  '2026-06-23'),
('JUEGOLEYENDA',     'visita',  '2026-06-24'),
('ORGULLODEMEX',     'visita',  '2026-06-25'),
('CIELOFUTBOL',      'visita',  '2026-06-26'),
('RAIZAZTECA',       'visita',  '2026-06-27'),
('TREINTAYDOSAVOS',  'visita',  '2026-06-28'),
('AGUILAALCIELO',    'visita',  '2026-06-29'),
('GLORIAVERDE',      'visita',  '2026-06-30'),
('SOLDEMEXICO',      'visita',  '2026-07-01'),
('ASTROFUTBOL',      'visita',  '2026-07-02'),
('FINDEDIECISEIS',   'visita',  '2026-07-03'),
('OCTAVOSAQUI',      'visita',  '2026-07-04'),
('RUTAGLORIA',       'visita',  '2026-07-05'),
('LEYENDAVIVA',      'visita',  '2026-07-06'),
('DESTINOAZTECA',    'visita',  '2026-07-07'),
('PAUSATITAN',       'visita',  '2026-07-08'),
('CUARTOSGRITO',     'visita',  '2026-07-09'),
('TIERRACAMPEONA',   'visita',  '2026-07-10'),
('AGUILAFUERTE',     'visita',  '2026-07-11'),
('ENTRESEMANAS',     'visita',  '2026-07-12'),
('PREVIASEMIS',      'visita',  '2026-07-13'),
('SEMIVERDE',        'visita',  '2026-07-14'),
('SEMIPASION',       'visita',  '2026-07-15'),
('SUSPENSOROJO',     'visita',  '2026-07-16'),
('SUSPENSOAZUL',     'visita',  '2026-07-17'),
('TERCERLUGAR',      'visita',  '2026-07-18'),
('FINALDETODOS',     'visita',  '2026-07-19'),
-- CONSUMO (uno por día)
('BRINDISARRANQUE',  'consumo', '2026-06-11'),
('TEQUILAFIRSTGOL',  'consumo', '2026-06-12'),
('CHELAINICIO',      'consumo', '2026-06-13'),
('TACOSDEORO',       'consumo', '2026-06-14'),
('BIRRIATITAN',      'consumo', '2026-06-15'),
('MEZCALAZTECA',     'consumo', '2026-06-16'),
('PASTORDELGOL',     'consumo', '2026-06-17'),
('SALSAVERDEGOL',    'consumo', '2026-06-18'),
('TAQUIZAMUNDIAL',   'consumo', '2026-06-19'),
('CARNEASADAFAN',    'consumo', '2026-06-20'),
('MOLECAMPEON',      'consumo', '2026-06-21'),
('POZOLEMEX',        'consumo', '2026-06-22'),
('TAMALORO',         'consumo', '2026-06-23'),
('ENCHILADAGOL',     'consumo', '2026-06-24'),
('CHILAQUILMEX',     'consumo', '2026-06-25'),
('NACHOSCAMPEON',    'consumo', '2026-06-26'),
('CHURROSDORADOS',   'consumo', '2026-06-27'),
('AGUAFRESCAFAN',    'consumo', '2026-06-28'),
('PALOMAMUNDIAL',    'consumo', '2026-06-29'),
('MICHELADATITAN',   'consumo', '2026-06-30'),
('CARAJILLOGOL',     'consumo', '2026-07-01'),
('SANGRIATRICOLOR',  'consumo', '2026-07-02'),
('MOJITOMEX',        'consumo', '2026-07-03'),
('FLANMUNDIAL',      'consumo', '2026-07-04'),
('POSTRECAMPEON',    'consumo', '2026-07-05'),
('LIMONADAGOLERA',   'consumo', '2026-07-06'),
('AZTECASHOT',       'consumo', '2026-07-07'),
('TROPICALMEX',      'consumo', '2026-07-08'),
('MEZCALITORICO',    'consumo', '2026-07-09'),
('CAFEDEMEX',        'consumo', '2026-07-10'),
('SHOTAZTECA',       'consumo', '2026-07-11'),
('TEQUILACAMPEON',   'consumo', '2026-07-12'),
('BIRRIAEPICA',      'consumo', '2026-07-13'),
('NACHOSDIVINOS',    'consumo', '2026-07-14'),
('ENCHILADASMEX',    'consumo', '2026-07-15'),
('TAQUERIAGOL',      'consumo', '2026-07-16'),
('CERVEZACORTE',     'consumo', '2026-07-17'),
('SEMIBRINDIS',      'consumo', '2026-07-18'),
('COPABRINDIS',      'consumo', '2026-07-19');

-- ─── 5. RPC: canjear_codigo (validación de fecha + 1 vez por user) ─
DROP FUNCTION IF EXISTS public.canjear_codigo(TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.canjear_codigo(p_code TEXT, p_tipo TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_code    RECORD;
  v_today   DATE := (NOW() AT TIME ZONE 'America/Mexico_City')::DATE;
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

  INSERT INTO codigos_canjeados (code, user_id) VALUES (v_code.code, v_user_id);
  UPDATE profiles
    SET puntos_codigos = COALESCE(puntos_codigos, 0) + 15
    WHERE id = v_user_id;

  RETURN jsonb_build_object('ok', true, 'msg', '+15 puntos por ' || p_tipo || ' ✅');
END;
$$;

GRANT EXECUTE ON FUNCTION public.canjear_codigo(TEXT, TEXT) TO authenticated;

-- ─── 6. Refrescar schema cache ─────────────────────────────────────
NOTIFY pgrst, 'reload schema';
