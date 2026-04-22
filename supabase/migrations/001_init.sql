-- =====================================================================
-- QUINIELA MUNDIAL 2026 – La Corte
-- Migration: 001_init.sql
-- =====================================================================

-- ─── Extensions ────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─── Tables ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS profiles (
  id           UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre       TEXT NOT NULL,
  email        TEXT NOT NULL,
  tel          TEXT NOT NULL DEFAULT '',
  role         TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user','manager','admin')),
  puntos_codigos INT NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS matches (
  id           TEXT PRIMARY KEY,
  phase        TEXT NOT NULL CHECK (phase IN ('group','ko')),
  round        TEXT,           -- R32, R16, QF, SF, 3RD, FINAL  (ko only)
  group_letter TEXT,           -- A..L  (group only)
  label        TEXT NOT NULL,
  team_a       TEXT NOT NULL DEFAULT 'TBD',
  team_b       TEXT NOT NULL DEFAULT 'TBD',
  date         TIMESTAMPTZ NOT NULL,
  venue        TEXT NOT NULL DEFAULT '',
  score_a      INT,
  score_b      INT,
  first_scorer TEXT CHECK (first_scorer IN ('A','B','none') OR first_scorer IS NULL)
);

CREATE TABLE IF NOT EXISTS predicciones (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  match_id   TEXT NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  score_a    INT,
  score_b    INT,
  ganador    TEXT CHECK (ganador IN ('A','B','E') OR ganador IS NULL),
  primero    TEXT CHECK (primero IN ('A','B','none') OR primero IS NULL),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, match_id)
);

CREATE TABLE IF NOT EXISTS codigos (
  code        TEXT PRIMARY KEY,
  tipo        TEXT NOT NULL CHECK (tipo IN ('visita','consumo')),
  usado       BOOL NOT NULL DEFAULT FALSE,
  por_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── updated_at trigger ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS trg_predicciones_updated_at ON predicciones;
CREATE TRIGGER trg_predicciones_updated_at
  BEFORE UPDATE ON predicciones
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ─── Ranking view ──────────────────────────────────────────────────
CREATE OR REPLACE VIEW ranking AS
SELECT
  p.id,
  p.nombre,
  p.email,
  p.puntos_codigos,
  COALESCE(SUM(
    CASE WHEN pr.score_a IS NOT NULL
          AND pr.score_a = m.score_a
          AND pr.score_b = m.score_b
          AND m.score_a IS NOT NULL THEN 30 ELSE 0 END
    +
    CASE WHEN m.score_a IS NOT NULL AND pr.ganador IS NOT NULL AND (
           (pr.ganador = 'A' AND m.score_a > m.score_b) OR
           (pr.ganador = 'B' AND m.score_b > m.score_a) OR
           (pr.ganador = 'E' AND m.score_a = m.score_b)
         ) THEN 25 ELSE 0 END
    +
    CASE WHEN m.first_scorer IS NOT NULL
          AND pr.primero = m.first_scorer
          AND m.score_a IS NOT NULL THEN 10 ELSE 0 END
  ), 0) AS puntos_predicciones,
  COALESCE(SUM(
    CASE WHEN pr.score_a IS NOT NULL
          AND pr.score_a = m.score_a
          AND pr.score_b = m.score_b
          AND m.score_a IS NOT NULL THEN 30 ELSE 0 END
    +
    CASE WHEN m.score_a IS NOT NULL AND pr.ganador IS NOT NULL AND (
           (pr.ganador = 'A' AND m.score_a > m.score_b) OR
           (pr.ganador = 'B' AND m.score_b > m.score_a) OR
           (pr.ganador = 'E' AND m.score_a = m.score_b)
         ) THEN 25 ELSE 0 END
    +
    CASE WHEN m.first_scorer IS NOT NULL
          AND pr.primero = m.first_scorer
          AND m.score_a IS NOT NULL THEN 10 ELSE 0 END
  ), 0) + COALESCE(p.puntos_codigos, 0) AS total_puntos
FROM profiles p
LEFT JOIN predicciones pr ON pr.user_id = p.id
LEFT JOIN matches m ON m.id = pr.match_id
GROUP BY p.id, p.nombre, p.email, p.puntos_codigos
ORDER BY total_puntos DESC;

-- ─── RPC: canjear código (atomic check-and-mark) ───────────────────
CREATE OR REPLACE FUNCTION canjear_codigo(p_code TEXT, p_tipo TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c codigos;
  uid UUID := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RETURN json_build_object('ok', false, 'msg', 'No autenticado');
  END IF;

  SELECT * INTO c FROM codigos WHERE code = UPPER(p_code) FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('ok', false, 'msg', 'Código inválido');
  END IF;
  IF c.tipo != p_tipo THEN
    RETURN json_build_object('ok', false, 'msg', 'Ese código no es de ' || p_tipo);
  END IF;
  IF c.usado THEN
    RETURN json_build_object('ok', false, 'msg', 'Código ya utilizado');
  END IF;

  UPDATE codigos SET usado = TRUE, por_user_id = uid WHERE code = c.code;
  UPDATE profiles SET puntos_codigos = puntos_codigos + 15 WHERE id = uid;

  RETURN json_build_object('ok', true, 'msg', '+15 puntos ganados');
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION canjear_codigo(TEXT, TEXT) TO authenticated;

-- ─── Enable RLS ────────────────────────────────────────────────────
ALTER TABLE profiles     ENABLE ROW LEVEL SECURITY;
ALTER TABLE matches      ENABLE ROW LEVEL SECURITY;
ALTER TABLE predicciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE codigos      ENABLE ROW LEVEL SECURITY;

-- ─── profiles policies ─────────────────────────────────────────────
CREATE POLICY "profiles: anyone authenticated can read"
  ON profiles FOR SELECT TO authenticated USING (true);

CREATE POLICY "profiles: users can insert own"
  ON profiles FOR INSERT TO authenticated
  WITH CHECK (id = auth.uid());

CREATE POLICY "profiles: users can update own; admins can update any"
  ON profiles FOR UPDATE TO authenticated
  USING (
    id = auth.uid()
    OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- ─── matches policies ──────────────────────────────────────────────
CREATE POLICY "matches: public read"
  ON matches FOR SELECT USING (true);

CREATE POLICY "matches: admin/manager can update"
  ON matches FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role IN ('admin','manager')
    )
  );

CREATE POLICY "matches: admin can insert"
  ON matches FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "matches: admin can delete"
  ON matches FOR DELETE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- ─── predicciones policies ─────────────────────────────────────────
-- All authenticated users can read all predictions (needed for ranking view)
CREATE POLICY "predicciones: authenticated can read all"
  ON predicciones FOR SELECT TO authenticated USING (true);

CREATE POLICY "predicciones: users can insert own"
  ON predicciones FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "predicciones: users can update own"
  ON predicciones FOR UPDATE TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "predicciones: users can delete own"
  ON predicciones FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ─── codigos policies ──────────────────────────────────────────────
CREATE POLICY "codigos: authenticated can read"
  ON codigos FOR SELECT TO authenticated USING (true);

CREATE POLICY "codigos: admin can insert"
  ON codigos FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "codigos: admin can delete"
  ON codigos FOR DELETE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- Update is handled via canjear_codigo() SECURITY DEFINER function, no direct UPDATE policy needed

-- Grant SELECT on ranking view to authenticated
GRANT SELECT ON ranking TO authenticated;

-- ─── Seed data: all 104 matches ────────────────────────────────────
-- Group phase (G1..G72) – times are in CST (UTC-6)
INSERT INTO matches (id, phase, group_letter, label, team_a, team_b, date, venue) VALUES
-- JUN 11
('G1','group','A','Grupo A','MEX','RSA','2026-06-11 13:00:00-06','Estadio Azteca, CDMX'),
('G2','group','A','Grupo A','KOR','CZE','2026-06-11 20:00:00-06','Estadio Akron, Guadalajara'),
-- JUN 12
('G3','group','B','Grupo B','CAN','BIH','2026-06-12 13:00:00-06','BMO Field, Toronto'),
('G4','group','D','Grupo D','USA','PAR','2026-06-12 19:00:00-06','SoFi Stadium, Inglewood'),
-- JUN 13
('G5','group','B','Grupo B','QAT','SUI','2026-06-13 13:00:00-06','Levi''s Stadium, Santa Clara'),
('G6','group','C','Grupo C','BRA','MAR','2026-06-13 16:00:00-06','MetLife Stadium, East Rutherford'),
('G7','group','C','Grupo C','HAI','SCO','2026-06-13 19:00:00-06','Gillette Stadium, Foxborough'),
('G8','group','D','Grupo D','AUS','TUR','2026-06-13 22:00:00-06','BC Place, Vancouver'),
-- JUN 14
('G9','group','E','Grupo E','GER','CUW','2026-06-14 11:00:00-06','NRG Stadium, Houston'),
('G10','group','F','Grupo F','NED','JPN','2026-06-14 14:00:00-06','AT&T Stadium, Arlington'),
('G11','group','E','Grupo E','CIV','ECU','2026-06-14 17:00:00-06','Lincoln Financial Field, Filadelfia'),
('G12','group','F','Grupo F','SWE','TUN','2026-06-14 20:00:00-06','Estadio BBVA, Monterrey'),
-- JUN 15
('G13','group','H','Grupo H','ESP','CPV','2026-06-15 10:00:00-06','Mercedes-Benz Stadium, Atlanta'),
('G14','group','G','Grupo G','BEL','EGY','2026-06-15 13:00:00-06','Lumen Field, Seattle'),
('G15','group','H','Grupo H','KSA','URU','2026-06-15 16:00:00-06','Hard Rock Stadium, Miami'),
('G16','group','G','Grupo G','IRN','NZL','2026-06-15 19:00:00-06','SoFi Stadium, Inglewood'),
-- JUN 16
('G17','group','I','Grupo I','FRA','SEN','2026-06-16 13:00:00-06','MetLife Stadium, East Rutherford'),
('G18','group','I','Grupo I','IRQ','NOR','2026-06-16 16:00:00-06','Gillette Stadium, Foxborough'),
('G19','group','J','Grupo J','ARG','ALG','2026-06-16 19:00:00-06','Arrowhead Stadium, Kansas City'),
('G20','group','J','Grupo J','AUT','JOR','2026-06-16 22:00:00-06','Levi''s Stadium, Santa Clara'),
-- JUN 17
('G21','group','K','Grupo K','POR','COD','2026-06-17 11:00:00-06','NRG Stadium, Houston'),
('G22','group','L','Grupo L','ENG','CRO','2026-06-17 14:00:00-06','AT&T Stadium, Arlington'),
('G23','group','L','Grupo L','GHA','PAN','2026-06-17 17:00:00-06','BMO Field, Toronto'),
('G24','group','K','Grupo K','UZB','COL','2026-06-17 20:00:00-06','Estadio Azteca, CDMX'),
-- JUN 18 (jornada 2)
('G25','group','A','Grupo A','CZE','RSA','2026-06-18 10:00:00-06','Mercedes-Benz Stadium, Atlanta'),
('G26','group','B','Grupo B','SUI','BIH','2026-06-18 13:00:00-06','SoFi Stadium, Inglewood'),
('G27','group','B','Grupo B','CAN','QAT','2026-06-18 16:00:00-06','BC Place, Vancouver'),
('G28','group','A','Grupo A','MEX','KOR','2026-06-18 19:00:00-06','Estadio Akron, Guadalajara'),
-- JUN 19
('G29','group','D','Grupo D','USA','AUS','2026-06-19 13:00:00-06','Lumen Field, Seattle'),
('G30','group','C','Grupo C','SCO','MAR','2026-06-19 16:00:00-06','Gillette Stadium, Foxborough'),
('G31','group','C','Grupo C','BRA','HAI','2026-06-19 18:30:00-06','Lincoln Financial Field, Filadelfia'),
('G32','group','D','Grupo D','TUR','PAR','2026-06-19 21:00:00-06','Levi''s Stadium, Santa Clara'),
-- JUN 20
('G33','group','F','Grupo F','NED','SWE','2026-06-20 11:00:00-06','NRG Stadium, Houston'),
('G34','group','E','Grupo E','GER','CIV','2026-06-20 14:00:00-06','BMO Field, Toronto'),
('G35','group','E','Grupo E','ECU','CUW','2026-06-20 20:00:00-06','Arrowhead Stadium, Kansas City'),
('G36','group','F','Grupo F','TUN','JPN','2026-06-20 22:00:00-06','Estadio BBVA, Monterrey'),
-- JUN 21
('G37','group','H','Grupo H','ESP','KSA','2026-06-21 10:00:00-06','Mercedes-Benz Stadium, Atlanta'),
('G38','group','G','Grupo G','BEL','IRN','2026-06-21 13:00:00-06','SoFi Stadium, Inglewood'),
('G39','group','H','Grupo H','URU','CPV','2026-06-21 16:00:00-06','Hard Rock Stadium, Miami'),
('G40','group','G','Grupo G','NZL','EGY','2026-06-21 19:00:00-06','BC Place, Vancouver'),
-- JUN 22
('G41','group','J','Grupo J','ARG','AUT','2026-06-22 11:00:00-06','AT&T Stadium, Arlington'),
('G42','group','I','Grupo I','FRA','IRQ','2026-06-22 15:00:00-06','Lincoln Financial Field, Filadelfia'),
('G43','group','I','Grupo I','NOR','SEN','2026-06-22 18:00:00-06','MetLife Stadium, East Rutherford'),
('G44','group','J','Grupo J','JOR','ALG','2026-06-22 21:00:00-06','Levi''s Stadium, Santa Clara'),
-- JUN 23
('G45','group','K','Grupo K','POR','UZB','2026-06-23 11:00:00-06','NRG Stadium, Houston'),
('G46','group','L','Grupo L','ENG','GHA','2026-06-23 14:00:00-06','Gillette Stadium, Foxborough'),
('G47','group','L','Grupo L','PAN','CRO','2026-06-23 17:00:00-06','BMO Field, Toronto'),
('G48','group','K','Grupo K','COL','COD','2026-06-23 20:00:00-06','Estadio Akron, Guadalajara'),
-- JUN 24 (jornada 3 simultánea)
('G49','group','B','Grupo B','SUI','CAN','2026-06-24 13:00:00-06','BC Place, Vancouver'),
('G50','group','B','Grupo B','BIH','QAT','2026-06-24 13:00:00-06','Lumen Field, Seattle'),
('G51','group','C','Grupo C','MAR','HAI','2026-06-24 16:00:00-06','Mercedes-Benz Stadium, Atlanta'),
('G52','group','C','Grupo C','SCO','BRA','2026-06-24 16:00:00-06','Hard Rock Stadium, Miami'),
('G53','group','A','Grupo A','RSA','KOR','2026-06-24 19:00:00-06','Estadio BBVA, Monterrey'),
('G54','group','A','Grupo A','CZE','MEX','2026-06-24 19:00:00-06','Estadio Azteca, CDMX'),
-- JUN 25
('G55','group','E','Grupo E','CUW','CIV','2026-06-25 14:00:00-06','Lincoln Financial Field, Filadelfia'),
('G56','group','E','Grupo E','ECU','GER','2026-06-25 14:00:00-06','MetLife Stadium, East Rutherford'),
('G57','group','F','Grupo F','JPN','SWE','2026-06-25 17:00:00-06','AT&T Stadium, Arlington'),
('G58','group','F','Grupo F','TUN','NED','2026-06-25 17:00:00-06','Arrowhead Stadium, Kansas City'),
('G59','group','D','Grupo D','PAR','AUS','2026-06-25 20:00:00-06','Levi''s Stadium, Santa Clara'),
('G60','group','D','Grupo D','TUR','USA','2026-06-25 20:00:00-06','SoFi Stadium, Inglewood'),
-- JUN 26
('G61','group','I','Grupo I','NOR','FRA','2026-06-26 13:00:00-06','Gillette Stadium, Foxborough'),
('G62','group','I','Grupo I','SEN','IRQ','2026-06-26 13:00:00-06','BMO Field, Toronto'),
('G63','group','H','Grupo H','CPV','KSA','2026-06-26 18:00:00-06','NRG Stadium, Houston'),
('G64','group','H','Grupo H','URU','ESP','2026-06-26 18:00:00-06','Estadio Akron, Guadalajara'),
('G65','group','G','Grupo G','EGY','IRN','2026-06-26 21:00:00-06','Lumen Field, Seattle'),
('G66','group','G','Grupo G','NZL','BEL','2026-06-26 21:00:00-06','BC Place, Vancouver'),
-- JUN 27
('G67','group','L','Grupo L','CRO','GHA','2026-06-27 15:00:00-06','Lincoln Financial Field, Filadelfia'),
('G68','group','L','Grupo L','PAN','ENG','2026-06-27 15:00:00-06','MetLife Stadium, East Rutherford'),
('G69','group','K','Grupo K','COL','POR','2026-06-27 17:30:00-06','Hard Rock Stadium, Miami'),
('G70','group','K','Grupo K','COD','UZB','2026-06-27 17:30:00-06','Mercedes-Benz Stadium, Atlanta'),
('G71','group','J','Grupo J','ALG','AUT','2026-06-27 20:00:00-06','Arrowhead Stadium, Kansas City'),
('G72','group','J','Grupo J','JOR','ARG','2026-06-27 20:00:00-06','AT&T Stadium, Arlington')
ON CONFLICT (id) DO NOTHING;

-- KO phase
INSERT INTO matches (id, phase, round, label, team_a, team_b, date, venue) VALUES
-- R32 – Dieciseisavos (JUN 28 – JUL 3)
('R32-1','ko','R32','Dieciseisavos','TBD','TBD','2026-06-28 11:00:00-06','Estadio Azteca, CDMX'),
('R32-2','ko','R32','Dieciseisavos','TBD','TBD','2026-06-28 15:00:00-06','Mercedes-Benz Stadium, Atlanta'),
('R32-3','ko','R32','Dieciseisavos','TBD','TBD','2026-06-28 19:00:00-06','MetLife Stadium, East Rutherford'),
('R32-4','ko','R32','Dieciseisavos','TBD','TBD','2026-06-29 11:00:00-06','BMO Field, Toronto'),
('R32-5','ko','R32','Dieciseisavos','TBD','TBD','2026-06-29 15:00:00-06','Hard Rock Stadium, Miami'),
('R32-6','ko','R32','Dieciseisavos','TBD','TBD','2026-06-29 19:00:00-06','SoFi Stadium, Inglewood'),
('R32-7','ko','R32','Dieciseisavos','TBD','TBD','2026-06-30 11:00:00-06','Estadio Akron, Guadalajara'),
('R32-8','ko','R32','Dieciseisavos','TBD','TBD','2026-06-30 15:00:00-06','NRG Stadium, Houston'),
('R32-9','ko','R32','Dieciseisavos','TBD','TBD','2026-06-30 19:00:00-06','Lincoln Financial Field, Filadelfia'),
('R32-10','ko','R32','Dieciseisavos','TBD','TBD','2026-07-01 11:00:00-06','Gillette Stadium, Foxborough'),
('R32-11','ko','R32','Dieciseisavos','TBD','TBD','2026-07-01 15:00:00-06','Arrowhead Stadium, Kansas City'),
('R32-12','ko','R32','Dieciseisavos','TBD','TBD','2026-07-01 19:00:00-06','BC Place, Vancouver'),
('R32-13','ko','R32','Dieciseisavos','TBD','TBD','2026-07-02 11:00:00-06','Estadio BBVA, Monterrey'),
('R32-14','ko','R32','Dieciseisavos','TBD','TBD','2026-07-02 15:00:00-06','AT&T Stadium, Arlington'),
('R32-15','ko','R32','Dieciseisavos','TBD','TBD','2026-07-03 11:00:00-06','Levi''s Stadium, Santa Clara'),
('R32-16','ko','R32','Dieciseisavos','TBD','TBD','2026-07-03 15:00:00-06','Lumen Field, Seattle'),
-- R16 – Octavos
('R16-1','ko','R16','Octavos de Final','TBD','TBD','2026-07-04 11:00:00-06','Hard Rock Stadium, Miami'),
('R16-2','ko','R16','Octavos de Final','TBD','TBD','2026-07-04 15:00:00-06','Mercedes-Benz Stadium, Atlanta'),
('R16-3','ko','R16','Octavos de Final','TBD','TBD','2026-07-05 11:00:00-06','Lincoln Financial Field, Filadelfia'),
('R16-4','ko','R16','Octavos de Final','TBD','TBD','2026-07-05 15:00:00-06','Estadio Azteca, CDMX'),
('R16-5','ko','R16','Octavos de Final','TBD','TBD','2026-07-06 11:00:00-06','AT&T Stadium, Arlington'),
('R16-6','ko','R16','Octavos de Final','TBD','TBD','2026-07-06 15:00:00-06','MetLife Stadium, East Rutherford'),
('R16-7','ko','R16','Octavos de Final','TBD','TBD','2026-07-07 11:00:00-06','SoFi Stadium, Inglewood'),
('R16-8','ko','R16','Octavos de Final','TBD','TBD','2026-07-07 15:00:00-06','Gillette Stadium, Foxborough'),
-- QF – Cuartos
('QF-1','ko','QF','Cuartos de Final','TBD','TBD','2026-07-09 15:00:00-06','AT&T Stadium, Arlington'),
('QF-2','ko','QF','Cuartos de Final','TBD','TBD','2026-07-09 19:00:00-06','Hard Rock Stadium, Miami'),
('QF-3','ko','QF','Cuartos de Final','TBD','TBD','2026-07-10 15:00:00-06','Gillette Stadium, Foxborough'),
('QF-4','ko','QF','Cuartos de Final','TBD','TBD','2026-07-11 15:00:00-06','SoFi Stadium, Inglewood'),
-- SF – Semis
('SF-1','ko','SF','Semifinal','TBD','TBD','2026-07-14 15:00:00-06','AT&T Stadium, Arlington'),
('SF-2','ko','SF','Semifinal','TBD','TBD','2026-07-15 15:00:00-06','MetLife Stadium, East Rutherford'),
-- 3er lugar / Final
('3RD','ko','3RD','Tercer Lugar','TBD','TBD','2026-07-18 14:00:00-06','Hard Rock Stadium, Miami'),
('FINAL','ko','FINAL','FINAL','TBD','TBD','2026-07-19 14:00:00-06','MetLife Stadium, East Rutherford')
ON CONFLICT (id) DO NOTHING;

-- ─── Seed data: demo codes ─────────────────────────────────────────
INSERT INTO codigos (code, tipo) VALUES
('VISITA01','visita'),('VISITA02','visita'),('VISITA03','visita'),
('CONSUMO01','consumo'),('CONSUMO02','consumo'),('CONSUMO03','consumo')
ON CONFLICT (code) DO NOTHING;
