-- =====================================================================
-- QUINIELA MUNDIAL 2026 – La Corte
-- Migration: 010_ranking_con_goleador.sql
--   · Vista `ranking` ahora incluye desglose de puntos por tipo:
--     · puntos_predicciones (30/25/10 por partido)
--     · puntos_visitas_consumos (15 visita + 20 consumo)
--     · puntos_goleador (15/30/45/60 según nivel)
--   · total_puntos sigue siendo la suma total
-- =====================================================================

CREATE OR REPLACE VIEW public.ranking AS
SELECT
  p.id,
  p.nombre,
  p.email,
  p.puntos_codigos,

  -- ── Puntos por predicciones (marcador + ganador + primer anotador) ──
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
  ), 0) AS puntos_predicciones,

  -- ── Puntos por visitas + consumos (no incluye goleador) ──
  COALESCE((
    SELECT SUM(CASE WHEN c.tipo = 'consumo' THEN 20 ELSE 15 END)
    FROM public.codigos_canjeados cc
    JOIN public.codigos c ON c.code = cc.code
    WHERE cc.user_id = p.id AND c.tipo IN ('visita','consumo')
  ), 0) AS puntos_visitas_consumos,

  -- ── Puntos por Bono Goleador (nueva promoción de cierre) ──
  COALESCE((
    SELECT SUM(COALESCE(c.puntos, 0))
    FROM public.codigos_canjeados cc
    JOIN public.codigos c ON c.code = cc.code
    WHERE cc.user_id = p.id AND c.tipo = 'goleador'
  ), 0) AS puntos_goleador,

  -- ── Total de puntos (predicciones + todos los folios) ──
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

NOTIFY pgrst, 'reload schema';
