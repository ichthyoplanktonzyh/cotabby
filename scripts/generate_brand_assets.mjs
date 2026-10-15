#!/usr/bin/env node

/**
 * Rebuild Lingrove's shipped logo and app-icon renditions from the approved
 * vector master in assets/branding. Sharp stays an explicit optional tool so
 * this asset pipeline does not add a runtime dependency to the app or repo.
 */

import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs/promises';

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..');
const require = createRequire(import.meta.url);
const masterPath = path.join(repoRoot, 'assets/branding/lingrove-logo.svg');
const activationIndicatorMasterPath = path.join(repoRoot, 'assets/branding/lingrove-activation-indicator.svg');

function sharpModuleArgument(argv) {
  const index = argv.indexOf('--sharp-module');
  if (index === -1) return undefined;
  const modulePath = argv[index + 1];
  if (!modulePath || modulePath.startsWith('--')) {
    throw new Error('--sharp-module requires a module path.');
  }
  return path.resolve(modulePath);
}

const sharpPath = sharpModuleArgument(process.argv.slice(2));
const sharp = sharpPath ? require(sharpPath) : require('sharp');

const info = { author: 'xcode', version: 1 };
const scales = [1, 2, 3];

function imageSetContents(name, template = false) {
  const contents = {
    images: scales.map((scale) => ({
      filename: `${name}${scale === 1 ? '' : `@${scale}x`}.png`,
      idiom: 'universal',
      scale: `${scale}x`,
    })),
    info,
  };
  if (template) contents.properties = { 'template-rendering-intent': 'template' };
  return `${JSON.stringify(contents, null, 2)}\n`;
}

function appIconContents() {
  const representations = [
    ['16x16', '1x', '16.png'],
    ['16x16', '2x', '32.png'],
    ['32x32', '1x', '32.png'],
    ['32x32', '2x', '64.png'],
    ['128x128', '1x', '128.png'],
    ['128x128', '2x', '256.png'],
    ['256x256', '1x', '256.png'],
    ['256x256', '2x', '512.png'],
    ['512x512', '1x', '512.png'],
    ['512x512', '2x', '1024.png'],
  ];
  return `${JSON.stringify({
    images: representations.map(([size, scale, filename]) => ({
      filename,
      idiom: 'mac',
      scale,
      size,
    })),
    info,
  }, null, 2)}\n`;
}

function svgWithDevBadge(master) {
  // The badge occupies empty space above the whale. It is a separate overlay,
  // so the approved whale paths and their colors remain untouched.
  const badge = `
  <g aria-label="Development build">
    <rect x="694" y="82" width="298" height="134" rx="67" fill="#F4B942" />
    <g fill="none" stroke="#174467" stroke-width="11" stroke-linecap="round" stroke-linejoin="round">
      <path d="M754 125v48h17c28 0 28-48 0-48z" />
      <path d="M817 125v48m0-48h39m-39 24h31m-31 24h39" />
      <path d="m876 125 18 48 18-48" />
    </g>
  </g>`;
  return master.replace('</svg>', `${badge}\n</svg>`);
}

function svgWithNavyMask(master) {
  // Xcode's template intent uses alpha as the tint mask. Converting navy paths
  // to white and the turquoise/white paths to black keeps the original navy
  // geometry while making the light regions transparent in the final icon.
  const mappedPaths = master
    .match(/<path\b[^>]*\/>/g)
    ?.map((pathElement) => pathElement.replace(/fill="(#[0-9A-Fa-f]{6})"/g, (_match, color) => {
      return color.toUpperCase() === '#174467' ? 'fill="#FFFFFF"' : 'fill="#000000"';
    })) ?? [];

  if (mappedPaths.length !== 5) {
    throw new Error(`Expected the approved master to contain 5 paths; found ${mappedPaths.length}.`);
  }
  const expectedColors = ['#174467', '#3CBFCF', '#FFFFFF', '#174467', '#3CBFCF'];
  const sourceColors = master.match(/fill="#[0-9A-Fa-f]{6}"/g)?.map((fill) => fill.slice(6, -1).toUpperCase()) ?? [];
  if (sourceColors.join(',') !== expectedColors.join(',')) {
    throw new Error('The approved master palette or path order changed; review the menu-bar mask mapping.');
  }

  // This centered square window removes only the master's empty outer margin.
  // Its bounds include the whole silhouette, so the 18px template stays sharp
  // without clipping the flukes or stretching the wide whale into a square.
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="8 34 960 960" width="1024" height="1024">
  <defs>
    <mask id="navy-only" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024" mask-type="luminance">
      <rect width="1024" height="1024" fill="#000000" />
      ${mappedPaths.join('\n      ')}
    </mask>
  </defs>
  <rect width="1024" height="1024" fill="#000000" mask="url(#navy-only)" />
</svg>`;
}

async function writePng(svg, destination, size) {
  await fs.mkdir(path.dirname(destination), { recursive: true });
  await sharp(Buffer.from(svg))
    .resize(size, size, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png({ compressionLevel: 9, adaptiveFiltering: false })
    .toFile(destination);
}

async function writeAlphaTemplatePng(svg, destination, size) {
  // The working SVG already has the target pixel dimensions. Rendering it
  // directly avoids rasterizing its original 200px canvas and shrinking twice.
  const rendered = await sharp(Buffer.from(svg)).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  if (rendered.info.width !== size || rendered.info.height !== size) {
    throw new Error(`Expected a ${size}x${size} activation-indicator render, got ${rendered.info.width}x${rendered.info.height}.`);
  }

  // Preserve only the antialiased alpha in black RGBA pixels. Template
  // consumers supply the foreground color instead of inheriting SVG colors.
  const pixels = Buffer.alloc(size * size * 4);
  for (let pixel = 0; pixel < size * size; pixel += 1) {
    pixels[pixel * 4 + 3] = rendered.data[pixel * rendered.info.channels + 3];
  }

  await fs.mkdir(path.dirname(destination), { recursive: true });
  await sharp(pixels, { raw: { width: size, height: size, channels: 4 } })
    .png({ compressionLevel: 9, adaptiveFiltering: false })
    .toFile(destination);
}

function activationIndicatorTemplateSvg(sourceSvg, pixelSize) {
  const pathElements = sourceSvg.match(/<path\b[^>]*>[\s\S]*?<\/path>/g) ?? [];
  if (pathElements.length !== 3) {
    throw new Error(`Expected the activation-indicator master to contain 3 paths; found ${pathElements.length}.`);
  }
  if (!sourceSvg.includes('viewBox="0 0 395 395"')) {
    throw new Error('The activation-indicator master viewBox changed; review the optical-size derivative.');
  }

  // The supplied master stays byte-for-byte unchanged. This working derivative
  // adds a 10-unit round-joined stroke to all three original paths and pads the
  // square viewBox by 5 units so the edge-to-edge rounded frame is not clipped.
  let derivative = sourceSvg.replace('viewBox="0 0 395 395"', 'viewBox="-5 -5 405 405"');
  for (const pathElement of pathElements) {
    const strokedPath = pathElement.replace(
      '<path ',
      '<path stroke="#000000" stroke-width="10" stroke-linecap="round" stroke-linejoin="round" ',
    );
    derivative = derivative.replace(pathElement, strokedPath);
  }

  // Setting the root dimensions before rasterization makes each PNG a direct
  // 1x/2x/3x vector render rather than a reduced copy of the 200px master.
  return derivative
    .replace('height="200px"', `height="${pixelSize}px"`)
    .replace('width="200px"', `width="${pixelSize}px"`);
}

async function writeImageSetContents(directory, name, template = false) {
  await fs.mkdir(directory, { recursive: true });
  await fs.writeFile(path.join(directory, 'Contents.json'), imageSetContents(name, template));
}

async function writeAppIconSet(directory, master, development = false) {
  await fs.mkdir(directory, { recursive: true });
  const iconSvg = development ? svgWithDevBadge(master) : master;
  for (const size of [16, 32, 64, 128, 256, 512, 1024]) {
    await writePng(iconSvg, path.join(directory, `${size}.png`), size);
  }
  await fs.writeFile(path.join(directory, 'Contents.json'), appIconContents());
}

async function main() {
  const master = await fs.readFile(masterPath, 'utf8');
  if (!master.includes('viewBox="0 0 1024 1024"')) {
    throw new Error(`Unexpected Lingrove logo master viewBox in ${masterPath}.`);
  }
  // Validate the path count, palette, and navy-to-mask mapping before creating
  // or replacing any output. A changed master must not leave a partial refresh.
  const menuMaskSvg = svgWithNavyMask(master);
  const activationIndicatorSvg = await fs.readFile(activationIndicatorMasterPath, 'utf8');
  const activationIndicatorMetadata = await sharp(Buffer.from(activationIndicatorSvg)).metadata();
  if (activationIndicatorMetadata.format !== 'svg' || !activationIndicatorMetadata.width || !activationIndicatorMetadata.height) {
    throw new Error(`Invalid activation-indicator SVG master at ${activationIndicatorMasterPath}.`);
  }
  const activationIndicatorRenditions = scales.map((scale) => {
    const pixelSize = 14 * scale;
    return { pixelSize, svg: activationIndicatorTemplateSvg(activationIndicatorSvg, pixelSize) };
  });
  for (const rendition of activationIndicatorRenditions) {
    const metadata = await sharp(Buffer.from(rendition.svg)).metadata();
    if (metadata.format !== 'svg' || metadata.width !== rendition.pixelSize || metadata.height !== rendition.pixelSize) {
      throw new Error(`Activation-indicator derivative did not resolve to ${rendition.pixelSize}x${rendition.pixelSize}.`);
    }
  }

  const assetsRoot = path.join(repoRoot, 'Cotabby/Assets.xcassets');
  const logoSet = path.join(assetsRoot, 'LingroveLogo.imageset');

  await writeImageSetContents(logoSet, 'LingroveLogo');
  for (const scale of scales) {
    await writePng(master, path.join(logoSet, `LingroveLogo${scale === 1 ? '' : `@${scale}x`}.png`), 128 * scale);
  }

  const menuSet = path.join(assetsRoot, 'MenuBarWhaleIcon.imageset');
  await writeImageSetContents(menuSet, 'MenuBarWhaleIcon', true);
  for (const scale of scales) {
    await writePng(menuMaskSvg, path.join(menuSet, `MenuBarWhaleIcon${scale === 1 ? '' : `@${scale}x`}.png`), 18 * scale);
  }

  const activationIndicatorSet = path.join(assetsRoot, 'ActivationIndicatorWhaleTail.imageset');
  await writeImageSetContents(activationIndicatorSet, 'ActivationIndicatorWhaleTail', true);
  for (const rendition of activationIndicatorRenditions) {
    const scale = rendition.pixelSize / 14;
    await writeAlphaTemplatePng(
      rendition.svg,
      path.join(activationIndicatorSet, `ActivationIndicatorWhaleTail${scale === 1 ? '' : `@${scale}x`}.png`),
      rendition.pixelSize,
    );
  }

  await writeAppIconSet(path.join(assetsRoot, 'AppIcon.appiconset'), master);
  await writeAppIconSet(path.join(assetsRoot, 'AppIconDev.appiconset'), master, true);
  await writePng(master, path.join(repoRoot, '.github/assets/readme/logo.png'), 512);

  console.log(`Generated branding assets with sharp ${sharp.versions.sharp}.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
