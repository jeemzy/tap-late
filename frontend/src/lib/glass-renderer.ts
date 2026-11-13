import { DEFAULT_GLASS, type GlassSettings } from "./glass-settings";

export type GlassFrame = {
  bounds: { x: number; y: number; width: number; height: number };
  scene: { x: number; y: number; width: number; height: number };
  radius: number;
  dpr: number;
  pointer: [number, number];
  energy: number;
  background: [number, number, number];
  reducedMotion: boolean;
  appearance?: GlassSettings;
};

const vertex = `
attribute vec2 aPosition;
varying vec2 vUv;
void main() {
  vUv = aPosition * 0.5 + 0.5;
  gl_Position = vec4(aPosition, 0.0, 1.0);
}`;

const fragment = `
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
varying vec2 vUv;
uniform sampler2D uSource;
uniform sampler2D uDiffuse;
uniform float uMatte;
uniform float uBodyPass;
uniform float uPadding;
uniform float uDiffusePadding;
uniform vec2 uSize;
uniform vec4 uBounds;
uniform vec4 uScene;
uniform float uRadius;
uniform float uPixel;
uniform vec2 uPointer;
uniform float uEnergy;
uniform float uFrost;
uniform float uIndex;
uniform float uBending;
uniform float uEdgeWidth;
uniform float uCurvature;
uniform float uMagnification;
uniform float uDispersion;
uniform float uGloss;
uniform float uReflection;
uniform vec3 uBackground;

vec3 sceneAt(vec2 viewport) {
  vec2 uv = (viewport - uScene.xy) / uScene.zw;
  if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return uBackground;
  return texture2D(uSource, uv).rgb;
}

void main() {
  // All geometry and optical offsets are CSS pixels, independent of backing DPR.
  vec2 local = vec2(vUv.x, 1.0 - vUv.y) * (uSize + 2.0 * uPadding) - uPadding;
  vec2 p = local - uSize * 0.5;
  float radius = min(uRadius, min(uSize.x, uSize.y) * 0.5);
  vec2 q = abs(p) - uSize * 0.5 + radius;
  vec2 corner = max(q, 0.0);
  float distance = length(corner) + min(max(q.x, q.y), 0.0) - radius;
  float coverage = 1.0 - smoothstep(-uPixel, uPixel, distance);
  if (coverage <= 0.0 && uBodyPass < 0.5) { gl_FragColor = vec4(0.0); return; }

  // Analytic normal of a rounded rectangle, including its straight sides.
  vec2 normal;
  if (length(corner) > 0.001) normal = normalize(corner) * sign(p);
  else normal = q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
  float depth = max(-distance, 0.0);
  float rimWidth = min(uEdgeWidth, min(uSize.x, uSize.y) * 0.40);
  float rim = exp(-depth / max(rimWidth * 0.48, 1.0));

  // Snell refraction through a convex front surface, strongest at the bevel.
  vec3 surface = normalize(vec3(normal * (uCurvature * rim), 1.0));
  vec3 ray = refract(vec3(0.0, 0.0, -1.0), surface, 1.0 / uIndex);
  vec2 bending = ray.xy / max(-ray.z, 0.2) * rimWidth * uBending * (1.0 + uEnergy * 0.075);
  vec2 sampleAt = uBounds.xy + uSize * 0.5 + p / (uMagnification + uEnergy * 0.005) + bending;

  // Clear polished glass: retain fine detail, with only a little surface roughness.
  float blur = uFrost * mix(1.0, 0.18, rim);
  // Paired, irregular taps avoid the clear stripes a regular kernel can alias into.
  vec2 a = vec2(0.36, 0.93) * blur * 1.33;
  vec2 b = vec2(-0.90, 0.31) * blur * 1.33;
  vec2 c = vec2(0.64, -0.54) * blur * 1.33;
  vec2 d = vec2(0.10, 0.35) * blur * 1.33;
  vec3 color = sceneAt(sampleAt) * 0.20;
  color += (sceneAt(sampleAt + a) + sceneAt(sampleAt - a)
          + sceneAt(sampleAt + b) + sceneAt(sampleAt - b)
          + sceneAt(sampleAt + c) + sceneAt(sampleAt - c)
          + sceneAt(sampleAt + d) + sceneAt(sampleAt - d)) * 0.10;

  // Dispersion is subpixel and limited to the refracting edge.
  vec2 fringe = normal * rim * uDispersion;
  color.r += (sceneAt(sampleAt + fringe).r - sceneAt(sampleAt).r) * rim * 0.45;
  color.b += (sceneAt(sampleAt - fringe).b - sceneAt(sampleAt).b) * rim * 0.45;
  // Capture the already refracted/warped color before scattering it. Padding
  // provides real neighboring colors rather than smearing a transparent edge.
  if (uBodyPass > 0.5) { gl_FragColor = vec4(color, 1.0); return; }
  if (uMatte > 0.0) {
    vec2 diffuseUv = (local + uDiffusePadding) / (uSize + 2.0 * uDiffusePadding);
    diffuseUv.y = 1.0 - diffuseUv.y;
    float finish = smoothstep(0.6, 4.0, depth) * min(uMatte * 4.0, 1.0);
    color = mix(color, texture2D(uDiffuse, diffuseUv).rgb, finish);
    // Neutral diffuse light gives the finish its mild milkiness. Specular
    // reflection and the polished outer rim remain independent layers below.
    color = mix(color, vec3(1.0), uMatte * 0.10);
  }
  // A small neutral surface reflection. Background colors come from the refracted
  // scene at each pixel, never a light/dark tint chosen for the entire surface.
  color = mix(color, vec3(1.0), uReflection * (1.0 + rim * 0.57));

  vec2 light = normalize(vec2(-0.65, -0.76) + (uPointer - 0.5) * 0.65);
  float facing = dot(normal, light);
  float edge = exp(-depth / 1.5);
  float inner = exp(-pow((depth - 3.2) / 2.2, 2.0));
  float specular = pow(max(facing, 0.0), 3.0);
  color += vec3(0.88, 0.94, 1.0) * edge * (0.10 + specular * 0.34) * uGloss;
  color += vec3(1.0) * inner * specular * (0.035 + uEnergy * 0.035) * uGloss;
  color -= edge * max(-facing, 0.0) * 0.035;
  gl_FragColor = vec4(clamp(color, 0.0, 1.0) * coverage, coverage);
}`;

const diffusionFragment = `
precision mediump float;
varying vec2 vUv;
uniform sampler2D uSource;
uniform vec2 uStep;
uniform float uSigma;
void main() {
  if (uSigma <= 0.0) {
    // Downsample progressively so text/stripes average into soft color, rather
    // than aliasing into large ghost shapes when the scattering radius grows.
    gl_FragColor = (texture2D(uSource, vUv + uStep * vec2(-0.5, -0.5))
      + texture2D(uSource, vUv + uStep * vec2(0.5, -0.5))
      + texture2D(uSource, vUv + uStep * vec2(-0.5, 0.5))
      + texture2D(uSource, vUv + uStep * vec2(0.5, 0.5))) * 0.25;
    return;
  }
  vec4 color = texture2D(uSource, vUv);
  float total = 1.0;
  for (int i = 1; i <= 12; i++) {
    float offset = float(i);
    float weight = exp(-0.5 * offset * offset / (uSigma * uSigma));
    color += (texture2D(uSource, vUv + uStep * offset)
      + texture2D(uSource, vUv - uStep * offset)) * weight;
    total += 2.0 * weight;
  }
  gl_FragColor = color / total;
}`;

type DiffusionTarget = { texture: WebGLTexture; width: number; height: number };

/** A captured-scene optical lens. Call setSource only when capture pixels change. */
export class GlassRenderer {
  private readonly gl: WebGLRenderingContext;
  private program: WebGLProgram | null = null;
  private buffer: WebGLBuffer | null = null;
  private texture: WebGLTexture | null = null;
  private diffusionProgram: WebGLProgram | null = null;
  private diffusionUniforms: Record<string, WebGLUniformLocation | null> = {};
  private diffusionFramebuffer: WebGLFramebuffer | null = null;
  private diffusionTargets: DiffusionTarget[] = [];
  private uniforms: Record<string, WebGLUniformLocation | null> = {};
  private source: HTMLCanvasElement | null = null;
  private lastFrame: GlassFrame | null = null;
  private textureWidth = 0;
  private textureHeight = 0;
  private lost = false;
  private disposed = false;

  constructor(private readonly canvas: HTMLCanvasElement) {
    const gl = canvas.getContext("webgl", {
      alpha: true,
      antialias: false,
      premultipliedAlpha: true,
      depth: false,
      stencil: false,
      preserveDrawingBuffer: false,
    });
    if (!gl) throw new Error("WebGL is unavailable");
    this.gl = gl;
    this.initialize();
    canvas.addEventListener("webglcontextlost", this.onLost);
    canvas.addEventListener("webglcontextrestored", this.onRestored);
  }

  private readonly onLost = (event: Event) => {
    event.preventDefault();
    this.lost = true;
  };

  private readonly onRestored = () => {
    if (this.disposed) return;
    try {
      this.release();
      this.initialize();
      this.lost = false;
      if (this.source) this.setSource(this.source);
      if (this.lastFrame) this.draw(this.lastFrame);
    } catch {
      this.release();
      this.lost = true;
    }
  };

  private initialize() {
    const gl = this.gl;
    const shaders: WebGLShader[] = [];
    try {
      const compile = (type: number, code: string) => {
        const shader = gl.createShader(type);
        if (!shader) throw new Error("Unable to allocate glass shader");
        shaders.push(shader);
        gl.shaderSource(shader, code);
        gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
          throw new Error(
            gl.getShaderInfoLog(shader) || "Glass shader compilation failed",
          );
        }
        return shader;
      };
      this.program = gl.createProgram();
      if (!this.program) throw new Error("Unable to allocate glass program");
      gl.attachShader(this.program, compile(gl.VERTEX_SHADER, vertex));
      gl.attachShader(this.program, compile(gl.FRAGMENT_SHADER, fragment));
      gl.linkProgram(this.program);
      if (!gl.getProgramParameter(this.program, gl.LINK_STATUS)) {
        throw new Error(
          gl.getProgramInfoLog(this.program) || "Glass shader linking failed",
        );
      }
      gl.useProgram(this.program);
      this.buffer = gl.createBuffer();
      this.texture = gl.createTexture();
      if (!this.buffer || !this.texture)
        throw new Error("Unable to allocate glass resources");
      gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
      gl.bufferData(
        gl.ARRAY_BUFFER,
        new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]),
        gl.STATIC_DRAW,
      );
      const position = gl.getAttribLocation(this.program, "aPosition");
      gl.enableVertexAttribArray(position);
      gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, this.texture);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      this.uniforms = {};
      for (const name of [
        "uSource",
        "uDiffuse",
        "uMatte",
        "uBodyPass",
        "uPadding",
        "uDiffusePadding",
        "uSize",
        "uBounds",
        "uScene",
        "uRadius",
        "uPixel",
        "uPointer",
        "uEnergy",
        "uFrost",
        "uIndex",
        "uBending",
        "uEdgeWidth",
        "uCurvature",
        "uMagnification",
        "uDispersion",
        "uGloss",
        "uReflection",
        "uBackground",
      ]) {
        this.uniforms[name] = gl.getUniformLocation(this.program, name);
      }
      gl.uniform1i(this.uniforms.uSource, 0);
      gl.uniform1i(this.uniforms.uDiffuse, 1);
      this.diffusionProgram = gl.createProgram();
      if (!this.diffusionProgram) throw new Error("Unable to allocate diffusion program");
      gl.attachShader(this.diffusionProgram, compile(gl.VERTEX_SHADER, vertex));
      gl.attachShader(this.diffusionProgram, compile(gl.FRAGMENT_SHADER, diffusionFragment));
      gl.linkProgram(this.diffusionProgram);
      if (!gl.getProgramParameter(this.diffusionProgram, gl.LINK_STATUS))
        throw new Error(gl.getProgramInfoLog(this.diffusionProgram) || "Diffusion shader linking failed");
      for (const name of ["uSource", "uStep", "uSigma"])
        this.diffusionUniforms[name] = gl.getUniformLocation(this.diffusionProgram, name);
      this.textureWidth = this.textureHeight = 0;
    } catch (error) {
      this.release();
      throw error;
    } finally {
      for (const shader of shaders) gl.deleteShader(shader);
    }
  }

  setSource(source: HTMLCanvasElement): void {
    if (this.disposed) return;
    this.source = source;
    if (this.lost || !source.width || !source.height) return;
    const gl = this.gl;
    const limit = gl.getParameter(gl.MAX_TEXTURE_SIZE) as number;
    let upload = source;
    if (Math.max(source.width, source.height) > limit) {
      upload = document.createElement("canvas");
      const scale = limit / Math.max(source.width, source.height);
      upload.width = Math.max(1, Math.floor(source.width * scale));
      upload.height = Math.max(1, Math.floor(source.height * scale));
      const context = upload.getContext("2d");
      if (!context) throw new Error("Unable to resize glass source");
      context.drawImage(source, 0, 0, upload.width, upload.height);
    }
    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    // DOM row zero is sampled at v=0; the fragment explicitly uses top-down UVs.
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    if (
      upload.width === this.textureWidth &&
      upload.height === this.textureHeight
    ) {
      gl.texSubImage2D(
        gl.TEXTURE_2D,
        0,
        0,
        0,
        gl.RGBA,
        gl.UNSIGNED_BYTE,
        upload,
      );
    } else {
      gl.texImage2D(
        gl.TEXTURE_2D,
        0,
        gl.RGBA,
        gl.RGBA,
        gl.UNSIGNED_BYTE,
        upload,
      );
      this.textureWidth = upload.width;
      this.textureHeight = upload.height;
    }
  }

  private useProgram(program: WebGLProgram) {
    const gl = this.gl;
    gl.useProgram(program);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
    const position = gl.getAttribLocation(program, "aPosition");
    gl.enableVertexAttribArray(position);
    gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
  }

  private diffusionTarget(index: number, width: number, height: number) {
    const gl = this.gl;
    if (!this.diffusionFramebuffer) {
      this.diffusionFramebuffer = gl.createFramebuffer();
      if (!this.diffusionFramebuffer) throw new Error("Unable to allocate diffusion framebuffer");
    }
    let target = this.diffusionTargets[index];
    if (!target) {
      const texture = gl.createTexture();
      if (!texture) throw new Error("Unable to allocate diffusion texture");
      target = { texture, width: 0, height: 0 };
      this.diffusionTargets[index] = target;
      gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    }
    if (target.width !== width || target.height !== height) {
      gl.bindTexture(gl.TEXTURE_2D, target.texture);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
      target.width = width; target.height = height;
    }
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.diffusionFramebuffer);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, target.texture, 0);
    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE)
      throw new Error("Diffusion framebuffer is incomplete");
    gl.viewport(0, 0, width, height);
    return target;
  }

  private scatter(width: number, height: number, matte: number) {
    const gl = this.gl, sigma = matte * 24, padding = Math.ceil(sigma * 3);
    const extentWidth = width + padding * 2, extentHeight = height + padding * 2;
    // Body capture is bounded to one CSS pixel per texel and at most 1 MP.
    // The small Gaussian targets stay at sigma <= 4 texels, independent of DPR.
    const density = Math.min(1, 1024 / Math.max(extentWidth, extentHeight),
      Math.sqrt(1_000_000 / (extentWidth * extentHeight)));
    let index = 0;
    let target = this.diffusionTarget(index++, Math.max(1, Math.ceil(extentWidth * density)),
      Math.max(1, Math.ceil(extentHeight * density)));
    this.useProgram(this.program!);
    gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, this.texture);
    gl.uniform1f(this.uniforms.uPadding, padding);
    gl.uniform1f(this.uniforms.uBodyPass, 1);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    this.useProgram(this.diffusionProgram!);
    const u = this.diffusionUniforms;
    gl.uniform1i(u.uSource, 0);
    const finalDensity = Math.min(density, 4 / Math.max(sigma, 0.01));
    const finalWidth = Math.max(1, Math.ceil(extentWidth * finalDensity));
    const finalHeight = Math.max(1, Math.ceil(extentHeight * finalDensity));
    while (target.width > finalWidth || target.height > finalHeight) {
      const previous = target;
      target = this.diffusionTarget(index++, Math.max(finalWidth, Math.ceil(previous.width / 2)),
        Math.max(finalHeight, Math.ceil(previous.height / 2)));
      gl.bindTexture(gl.TEXTURE_2D, previous.texture);
      gl.uniform2f(u.uStep, 1 / previous.width, 1 / previous.height);
      gl.uniform1f(u.uSigma, 0);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    }
    for (const horizontal of [true, false]) {
      const previous = target;
      target = this.diffusionTarget(index++, previous.width, previous.height);
      gl.bindTexture(gl.TEXTURE_2D, previous.texture);
      gl.uniform2f(u.uStep, horizontal ? 1 / previous.width : 0, horizontal ? 0 : 1 / previous.height);
      gl.uniform1f(u.uSigma, Math.max(0.01, sigma * (horizontal ? previous.width / extentWidth : previous.height / extentHeight)));
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    }
    // Geometry/radius changes can reduce the number of levels required.
    for (const unused of this.diffusionTargets.splice(index)) gl.deleteTexture(unused.texture);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    return { texture: target.texture, padding };
  }

  draw(frame: GlassFrame): boolean {
    if (this.disposed) return false;
    this.lastFrame = frame;
    if (this.lost || !this.textureWidth || this.gl.isContextLost())
      return false;
    const { bounds, scene } = frame;
    if (
      bounds.width <= 0 ||
      bounds.height <= 0 ||
      scene.width <= 0 ||
      scene.height <= 0
    )
      return false;
    const gl = this.gl;
    const dpr = Math.max(1, Math.min(3, frame.dpr || 1));
    const width = Math.max(1, Math.round(bounds.width * dpr));
    const height = Math.max(1, Math.round(bounds.height * dpr));
    if (this.canvas.width !== width) this.canvas.width = width;
    if (this.canvas.height !== height) this.canvas.height = height;
    this.useProgram(this.program!);
    const u = this.uniforms;
    const settings = frame.appearance ?? DEFAULT_GLASS;
    gl.uniform1f(u.uFrost, settings.frost);
    gl.uniform1f(u.uIndex, settings.refraction_index);
    gl.uniform1f(u.uBending, settings.refraction_strength);
    gl.uniform1f(u.uEdgeWidth, settings.edge_width);
    gl.uniform1f(u.uCurvature, settings.curvature);
    gl.uniform1f(u.uMagnification, settings.magnification);
    gl.uniform1f(u.uDispersion, settings.dispersion);
    gl.uniform1f(u.uGloss, settings.gloss);
    gl.uniform1f(u.uReflection, settings.reflection);
    gl.uniform2f(u.uSize, bounds.width, bounds.height);
    gl.uniform4f(u.uBounds, bounds.x, bounds.y, bounds.width, bounds.height);
    gl.uniform4f(u.uScene, scene.x, scene.y, scene.width, scene.height);
    gl.uniform1f(u.uRadius, Math.max(0, frame.radius));
    gl.uniform1f(u.uPixel, 0.75 / dpr);
    gl.uniform2f(u.uPointer, frame.pointer[0], frame.pointer[1]);
    gl.uniform1f(
      u.uEnergy,
      frame.reducedMotion ? 0 : Math.max(0, Math.min(2, frame.energy)),
    );
    gl.uniform3f(u.uBackground, ...frame.background);
    gl.uniform1f(u.uMatte, settings.matte);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    const scattered = settings.matte > 0 ? this.scatter(bounds.width, bounds.height, settings.matte) : null;
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, width, height);
    this.useProgram(this.program!);
    gl.uniform1f(u.uBodyPass, 0);
    gl.uniform1f(u.uPadding, 0);
    gl.uniform1f(u.uDiffusePadding, scattered?.padding ?? 0);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, scattered?.texture ?? this.texture);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    return true;
  }

  private release() {
    this.gl.deleteTexture(this.texture);
    this.gl.deleteBuffer(this.buffer);
    this.gl.deleteProgram(this.program);
    this.gl.deleteProgram(this.diffusionProgram);
    this.gl.deleteFramebuffer(this.diffusionFramebuffer);
    for (const target of this.diffusionTargets) this.gl.deleteTexture(target.texture);
    this.diffusionTargets = [];
    this.diffusionFramebuffer = this.diffusionProgram = null;
    this.texture = this.buffer = this.program = null;
    this.textureWidth = this.textureHeight = 0;
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.canvas.removeEventListener("webglcontextlost", this.onLost);
    this.canvas.removeEventListener("webglcontextrestored", this.onRestored);
    this.release();
    this.source = null;
    this.lastFrame = null;
  }
}
