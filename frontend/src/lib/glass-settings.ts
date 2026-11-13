export type GlassSettings = {
  frost: number;
  matte: number;
  refraction_index: number;
  refraction_strength: number;
  edge_width: number;
  curvature: number;
  magnification: number;
  dispersion: number;
  gloss: number;
  reflection: number;
  press_response: number;
  resolution: "auto" | "2x" | "3x";
};

export const DEFAULT_GLASS: GlassSettings = {
  frost: 1,
  matte: 0,
  refraction_index: 1.52,
  refraction_strength: 1.6,
  edge_width: 32,
  curvature: 2.1,
  magnification: 1.045,
  dispersion: 0.85,
  gloss: 1,
  reflection: 0.07,
  press_response: 1,
  resolution: "auto",
};

export function glassScale(resolution: GlassSettings["resolution"]) {
  return resolution === "3x"
    ? 3
    : resolution === "2x"
      ? 2
      : Math.min(Math.max(devicePixelRatio || 1, 2), 3);
}
