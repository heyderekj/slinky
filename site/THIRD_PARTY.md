# Third-party credits

The site's wallpaper and Liquid Glass (`src/scripts/glass.ts`) are Slinky's own code. They follow published techniques:

- **Mesh gradient:** colour points blended by inverse distance with a gentle swirl and grain, after Paper's MeshGradient shader (paper-design/shaders, Apache-2.0, https://github.com/paper-design/shaders). No code from it is included.
- **Liquid Glass recipe:** refraction in a thin rim band with a clear middle, per-channel colour split, and the inset box-shadow edge, from Jhey Tompkins' "liquid glass" (https://codepen.io/jh3y/pen/EajLxJV, MIT, Copyright (c) Jhey). Reworked as a WebGL shader.
- **Liquid Glass refraction:** a convex squircle bezel with refraction, specular rim and colour fringing, after Kube's "Liquid Glass in CSS and SVG" (https://kube.io/blog/liquid-glass-css-svg/) and Shu Ding's liquid-glass demo (MIT, https://github.com/shuding/liquid-glass).
- **Family design language:** tokens, motion and the mesh card palette format from heyderekj.com and testamentmade.com (Testament Made, LLC).
- **Font:** Figtree by Erik Kennedy, served by Google Fonts (SIL Open Font License).
