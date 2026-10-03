#!/usr/bin/env node
// Preserve the editable high-poly GLB; derive a mobile mesh without re-rigging.
// Install tools: npm install --prefix /tmp/pawpace-mesh-tools --no-audit --no-fund
//   @gltf-transform/core@4.5.0 @gltf-transform/functions@4.5.0
//   @gltf-transform/extensions@4.5.0 meshoptimizer@1.2.0
// Usage: node scripts/optimize_meshy_glb.mjs input.glb output.glb [triangles=30000] [error=0.02]
// PAWPACE_MESH_TOOLS can override the dependency directory.
// References: https://gltf-transform.dev/modules/functions/functions/simplify
// https://github.com/zeux/meshoptimizer/discussions/973
import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

const toolDirectory = process.env.PAWPACE_MESH_TOOLS || '/tmp/pawpace-mesh-tools';
const resolve = createRequire(path.join(toolDirectory, 'package.json')).resolve;
const { NodeIO } = await import(pathToFileURL(resolve('@gltf-transform/core')));
const { ALL_EXTENSIONS } = await import(pathToFileURL(resolve('@gltf-transform/extensions')));
const { weldPrimitive, compactPrimitive } = await import(pathToFileURL(resolve('@gltf-transform/functions')));
const { MeshoptSimplifier, MeshoptDecoder } = await import(pathToFileURL(resolve('meshoptimizer')));

function requireThat(value, message) { if (!value) throw new Error(message); }
function hash(data) { return createHash('sha256').update(data).digest('hex'); }
function glbJSON(data) {
    requireThat(data.readUInt32LE(0) === 0x46546c67 && data.readUInt32LE(12 + 4) === 0x4e4f534a, 'Expected binary glTF JSON chunk.');
    return JSON.parse(data.subarray(20, 20 + data.readUInt32LE(12)).toString('utf8'));
}
function restoreOriginalTransforms(sourceData, outputData) {
    const original = glbJSON(sourceData), result = glbJSON(outputData);
    requireThat(original.nodes.length === result.nodes.length, 'Serialization changed node count.');
    for (let index = 0; index < original.nodes.length; index++) {
        const before = original.nodes[index], after = result.nodes[index];
        requireThat(before.name === after.name && JSON.stringify(before.children || []) === JSON.stringify(after.children || []), 'Serialization reordered skeleton nodes.');
        // NodeIO may normalize near-unit exported rotations/scales while writing
        // TRS. Keep the exact authored transforms, not a normalized equivalent.
        for (const key of ['matrix', 'translation', 'rotation', 'scale']) {
            if (key in before) after[key] = before[key]; else delete after[key];
        }
    }
    const text = Buffer.from(JSON.stringify(result));
    const padded = Buffer.alloc(Math.ceil(text.length / 4) * 4, 0x20);
    text.copy(padded);
    const tail = outputData.subarray(20 + outputData.readUInt32LE(12));
    const header = Buffer.alloc(20);
    header.writeUInt32LE(0x46546c67, 0); header.writeUInt32LE(2, 4);
    header.writeUInt32LE(20 + padded.length + tail.length, 8);
    header.writeUInt32LE(padded.length, 12); header.writeUInt32LE(0x4e4f534a, 16);
    return Buffer.concat([header, padded, tail]);
}
function skeletonSignature(document) {
    const root = document.getRoot(), nodes = root.listNodes();
    return JSON.stringify({
        nodes: nodes.map(node => ({ name: node.getName(), matrix: node.getMatrix(),
            children: node.listChildren().map(child => nodes.indexOf(child)),
            skin: root.listSkins().indexOf(node.getSkin()) })),
        skins: root.listSkins().map(skin => ({ name: skin.getName(),
            joints: skin.listJoints().map(joint => nodes.indexOf(joint)),
            skeleton: nodes.indexOf(skin.getSkeleton()),
            inverseBinds: Array.from(skin.getInverseBindMatrices()?.getArray() || []) })),
        animations: root.listAnimations().map(animation => ({ name: animation.getName(),
            channels: animation.listChannels().map(channel => ({
                node: nodes.indexOf(channel.getTargetNode()), path: channel.getTargetPath(),
                interpolation: channel.getSampler().getInterpolation(),
                input: Array.from(channel.getSampler().getInput()?.getArray() || []),
                output: Array.from(channel.getSampler().getOutput()?.getArray() || []) })) })),
        images: root.listTextures().map(texture => hash(texture.getImage() || new Uint8Array()))
    });
}

function vertexAttributes(primitive) {
    const attributes = primitive.listSemantics().sort().map(name => [name, primitive.getAttribute(name)]);
    primitive.listTargets().forEach((target, index) => {
        for (const name of target.listSemantics().sort()) attributes.push([`target${index}:${name}`, target.getAttribute(name)]);
    });
    return attributes.map(([name, accessor]) => {
        const array = accessor.getArray();
        return { name, accessor, stride: accessor.getElementSize() * array.BYTES_PER_ELEMENT,
            bytes: Buffer.from(array.buffer, array.byteOffset, array.byteLength) };
    });
}

function vertexKey(attributes, index) {
    return attributes.map(attribute => attribute.bytes.subarray(index * attribute.stride, (index + 1) * attribute.stride).toString('base64')).join('|');
}

async function main() {
    const [inputArgument, outputArgument, targetArgument = '30000', errorArgument = '0.02'] = process.argv.slice(2);
    requireThat(inputArgument && outputArgument, 'Expected input.glb output.glb [target triangles] [error]');
    const input = path.resolve(inputArgument), output = path.resolve(outputArgument);
    requireThat(input !== output, 'High-poly source and optimized output must be different paths.');
    const target = Number(targetArgument), maximumError = Number(errorArgument);
    requireThat(Number.isInteger(target) && target >= 1000, 'Target triangles must be an integer >=1000.');
    requireThat(Number.isFinite(maximumError) && maximumError > 0 && maximumError <= 0.1, 'Error must be >0 and <=0.1.');
    const sourceData = await fs.readFile(input), sourceHash = hash(sourceData);
    const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({ 'meshopt.decoder': MeshoptDecoder });
    const document = await io.readBinary(sourceData);
    const root = document.getRoot(), skeletonBefore = skeletonSignature(document);
    requireThat(root.listSkins().length > 0, 'Expected a rigged source; refusing an unskinned replacement.');
    const primitives = root.listMeshes().flatMap(mesh => mesh.listPrimitives());
    const totalTriangles = primitives.reduce((sum, primitive) => sum + (primitive.getIndices()?.getCount() || primitive.getAttribute('POSITION').getCount()) / 3, 0);
    await MeshoptSimplifier.ready;
    const reports = [];
    for (const [primitiveIndex, primitive] of primitives.entries()) {
        requireThat(primitive.getMode() === 4, 'Only triangle primitives are supported.');
        const originalAttributes = vertexAttributes(primitive);
        const originalVertices = primitive.getAttribute('POSITION').getCount();
        const originalKeys = new Set(Array.from({ length: originalVertices }, (_, index) => vertexKey(originalAttributes, index)));
        const originalSemantics = primitive.listSemantics().sort();
        const skinSemantics = originalSemantics.filter(name => /^(JOINTS|WEIGHTS)_\d+$/.test(name));
        requireThat(skinSemantics.includes('JOINTS_0') && skinSemantics.includes('WEIGHTS_0'), 'Missing skin weight stream.');
        // weldPrimitive compares all attribute bytes, including every influence
        // set. It neither limits influence count nor normalizes skin weights.
        weldPrimitive(primitive, { overwrite: true });
        const positions = primitive.getAttribute('POSITION').getArray();
        requireThat(positions instanceof Float32Array, 'Expected unquantized Meshy positions.');
        const sourceIndices = new Uint32Array(primitive.getIndices().getArray());
        const targetTriangles = Math.max(1, Math.floor(target * (sourceIndices.length / 3) / totalTriangles));
        let resultIndices = sourceIndices, actualError = 0;
        if (sourceIndices.length > targetTriangles * 3) {
            // Index-only simplification reuses original vertices. Regularize is
            // the maintainer's recommendation for articulated/skinned meshes.
            // Bone indices and weights are deliberately NOT interpolated.
            [resultIndices, actualError] = MeshoptSimplifier.simplify(
                sourceIndices, positions, 3, targetTriangles * 3, maximumError, ['Regularize']);
            primitive.setIndices(document.createAccessor().setType('SCALAR').setArray(resultIndices).setBuffer(root.listBuffers()[0]));
            compactPrimitive(primitive);
        }
        requireThat(JSON.stringify(primitive.listSemantics().sort()) === JSON.stringify(originalSemantics), 'An attribute stream was lost.');
        const finalAttributes = vertexAttributes(primitive);
        const finalVertices = primitive.getAttribute('POSITION').getCount();
        for (let index = 0; index < finalVertices; index++) {
            requireThat(originalKeys.has(vertexKey(finalAttributes, index)), 'A surviving vertex or skin influence changed.');
        }
        reports.push({ primitive: primitiveIndex, sourceVertices: originalVertices,
            sourceTriangles: sourceIndices.length / 3, vertices: finalVertices,
            triangles: primitive.getIndices().getCount() / 3, geometricError: actualError,
            skinStreamsPreserved: skinSemantics, allSurvivingVertexAttributesExact: true });
    }
    requireThat(skeletonSignature(document) === skeletonBefore, 'Skeleton, bind matrices, transforms, or textures changed.');
    // Remove only accessors detached by the index replacement. Do not use prune
    // or an optimize preset: they may alter rigs, animations or influence limits.
    for (const accessor of root.listAccessors()) {
        if (accessor.listParents().length === 1) accessor.dispose();
    }
    const outputData = restoreOriginalTransforms(sourceData, Buffer.from(await io.writeBinary(document)));
    const reloaded = await io.readBinary(outputData);
    requireThat(skeletonSignature(reloaded) === skeletonBefore, 'Serialized output changed the skeleton or textures.');
    const serializedPrimitives = reloaded.getRoot().listMeshes().flatMap(mesh => mesh.listPrimitives());
    requireThat(serializedPrimitives.length === primitives.length, 'Serialization changed primitive count.');
    for (let index = 0; index < primitives.length; index++) {
        const before = vertexAttributes(primitives[index]), after = vertexAttributes(serializedPrimitives[index]);
        requireThat(before.length === after.length && before.every((attribute, i) =>
            attribute.name === after[i].name && attribute.stride === after[i].stride && attribute.bytes.equals(after[i].bytes)),
            'Serialization changed vertex attributes or skin weights.');
    }
    requireThat(hash(await fs.readFile(input)) === sourceHash, 'High-poly source unexpectedly changed.');
    await fs.mkdir(path.dirname(output), { recursive: true });
    await fs.writeFile(output, outputData);
    const report = { source: input, output, sourceSHA256: sourceHash, outputSHA256: hash(outputData),
        sourceBytes: sourceData.length, outputBytes: outputData.length, targetTriangles: target,
        maximumError, totalSourceTriangles: totalTriangles,
        totalTriangles: reports.reduce((sum, primitive) => sum + primitive.triangles, 0),
        skeletonAndInverseBindMatricesPreserved: true, embeddedTexturesPreserved: true,
        animationChannelsPreserved: true, serializedVertexAttributesExact: true,
        algorithms: ['exact attribute weld', 'meshoptimizer index-only simplify + Regularize', 'lossless attribute compaction'],
        primitives: reports };
    await fs.writeFile(output.replace(/\.glb$/i, '') + '.optimization.json', JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report, null, 2));
}

await main();
