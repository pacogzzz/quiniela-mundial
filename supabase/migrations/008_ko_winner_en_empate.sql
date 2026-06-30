-- =====================================================================
-- QUINIELA MUNDIAL 2026 – La Corte
-- Migration: 008_ko_winner_en_empate.sql
--   · Agrega columna `winner` (A o B) a matches para registrar el ganador
--     de un partido KO que terminó EMPATADO (definido por penales o TE)
--   · Actualiza la vista `ranking`:
--     · 30 pts si el marcador exacto coincide (incluye empates con penales)
--     · 25 pts si el ganador predicho coincide con el ganador real
--       - Si winner está seteado (penal/TE), gana ese equipo aunque score sea igual
--       - Si winner es NULL y score iguales → empate real (solo válido en grupos)
--     · 10 pts si primer anotador coincide
-- =====================================================================

-- ─── 1. Nueva columna ───────────────────────────────────────
ALTER TABLE public.matches
  ADD COLUMN IF NOT EXISTS winner TEXT
  CHECK (winner IN ('A','B') OR winner IS NULL);

-- ─── 2. Vista ranking actualizada ───────────────────────────
CREATE OR REPLACE VIEW public.ranking AS
SELECT
  p.id,
  p.nombre,
  p.email,
  p.puntos_codigos,
  COALESCE(SUM(
    -- Marcador exacto (30 pts)
    CASE WHEN pr.score_a IS NOT NULL
          AND pr.score_a = m.score_a
          AND pr.score_b = m.score_b
          AND m.score_a IS NOT NULL THEN 30 ELSE 0 END
    +
    -- Ganador (25 pts) — usando winner si hay, score si no
    CASE WHEN m.score_a IS NOT NULL AND pr.ganador IS NOT NULL AND (
           (pr.ganador = 'A' AND (m.score_a > m.score_b
                                  OR (m.score_a = m.score_b AND m.winner = 'A')))
        OR (pr.ganador = 'B' AND (m.score_b > m.score_a
                                  OR (m.score_a = m.score_b AND m.winner = 'B')))
        OR (pr.ganador = 'E' AND  m.score_a = m.score_b AND m.winner IS NULL)
         ) THEN 25 ELSE 0 END
    +
    -- Primer anotador (10 pts)
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
           (pr.ganador = 'A' AND (m.score_a > m.score_b
                                  OR (m.score_a = m.score_b AND m.winner = 'A')))
        OR (pr.ganador = 'B' AND (m.score_b > m.score_a
                                  OR (m.score_a = m.score_b AND m.winner = 'B')))
        OR (pr.ganador = 'E' AND  m.score_a = m.score_b AND m.winner IS NULL)
         ) THEN 25 ELSE 0 END
    +
    CASE WHEN m.first_scorer IS NOT NULL
          AND pr.primero = m.first_scorer
          AND m.score_a IS NOT NULL THEN 10 ELSE 0 END
  ), 0) + COALESCE(p.puntos_codigos, 0) AS total_puntos
FROM public.profiles p
LEFT JOIN public.predicciones pr ON pr.user_id = p.id
LEFT JOIN public.matches      m  ON m.id      = pr.match_id
GROUP BY p.id, p.nombre, p.email, p.puntos_codigos
ORDER BY total_puntos DESC;

-- ─── 3. Refrescar schema cache ─────────────────────────────
NOTIFY pgrst, 'reload schema';
